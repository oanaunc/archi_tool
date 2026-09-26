// Oanarina Archi Tool — GPL-3.0-or-later
// Thermal bridge hints (ANL-026): geometric linear thermal bridges of the envelope after EN ISO 14683 junction types —
// exterior wall corners (convex / re-entrant), ground floor edge, intermediate floor edges, balconies (slabs projecting
// beyond the facade), roof / eaves, window and door reveals, columns inside exterior walls. Each junction gets a length
// and a design ψ (W/m·K, typical default values for internal dimensions; override with drawing variables PSI:<kind>);
// H_TB = Σ ψ·L is compared with the envelope's transmission loss.
import Foundation

public struct ThermalBridge: Hashable {
    public var kind: String
    public var elements: [EntityID]
    public var length: Double      // m
    public var psi: Double         // W/m·K
    public var location: Vec2      // model units (a representative point)
    public var h: Double { psi * length }
}

public enum ThermalBridges {
    /// Default ψ values (W/m·K) — typical EN ISO 14683 table values, uninsulated junction details.
    public static let defaults: [String: Double] = [
        "corner": 0.10, "corner-reentrant": -0.05, "ground-floor": 0.60, "intermediate-floor": 0.40, "balcony": 0.90,
        "roof-eaves": 0.50, "window-reveal": 0.10, "door-reveal": 0.15, "column": 0.30,
    ]
    public static let titles: [String: String] = [
        "corner": "Exterior wall corner", "corner-reentrant": "Re-entrant wall corner", "ground-floor": "Wall / ground floor",
        "intermediate-floor": "Wall / intermediate floor", "balcony": "Balcony slab", "roof-eaves": "Wall / roof (eaves)",
        "window-reveal": "Window reveals", "door-reveal": "Door reveals", "column": "Column in exterior wall",
    ]
    public static func psi(_ kind: String, doc: ArchiDocument) -> Double {
        doc.variable("PSI:" + kind).flatMap(Double.init) ?? defaults[kind] ?? 0
    }

    public static func detect(_ doc: ArchiDocument) -> [ThermalBridge] {
        let m = doc.units.mm / 1000
        var out: [ThermalBridge] = []
        func add(_ kind: String, _ ids: [EntityID], _ lengthM: Double, _ at: Vec2) {
            guard lengthM > 1e-6 else { return }
            out.append(ThermalBridge(kind: kind, elements: ids, length: lengthM, psi: psi(kind, doc: doc), location: at))
        }
        let ext = doc.elements.filter { Thermal.isExterior($0, doc: doc) }
        let extWalls: [(el: BIMElement, w: WallGeom)] = ext.compactMap { el in if case .wall(let w) = el.geometry { return (el, w) }; return nil }
        let wallLevels = Set(extWalls.map(\.el.level))
        let levelsSorted = doc.levels.filter { wallLevels.contains($0.id) }.sorted { $0.elevation < $1.elevation }
        let lowest = levelsSorted.first?.id, highest = levelsSorted.last?.id

        // Building outline per level: rooms / slabs, else the hull of the exterior walls.
        func footprint(_ level: Int) -> [[Vec2]] {
            let slabs = doc.elements.compactMap { e -> [Vec2]? in
                guard e.level == level, case .slab(let s) = e.geometry, (e.props["kind"] ?? "") != "balcony" else { return nil }
                return s.boundary
            }
            let rooms = doc.elements.compactMap { e -> [Vec2]? in if e.level == level, case .space(let s) = e.geometry { return s.boundary }; return nil }
            if !rooms.isEmpty { return rooms }
            if !slabs.isEmpty { return slabs }
            let hull = Thermal.convexHull(extWalls.filter { $0.el.level == level }.flatMap { [$0.w.centerStart, $0.w.centerEnd] })
            return hull.count >= 3 ? [hull] : []
        }
        var fp: [Int: [[Vec2]]] = [:]
        for l in wallLevels { fp[l] = footprint(l) }
        func inside(_ p: Vec2, _ level: Int) -> Bool { (fp[level] ?? []).contains { GeometryOps.pointInPolygon(p, $0) } }

        // Corners: exterior wall ends meeting (within the wall thickness), not collinear.
        for i in 0..<extWalls.count {
            for j in (i + 1)..<max(i + 1, extWalls.count) {
                let (a, wa) = extWalls[i], (b, wb) = extWalls[j]
                guard a.level == b.level else { continue }
                let tol = max(wa.thickness, wb.thickness)
                var corner: (Vec2, Vec2, Vec2)?   // point, direction along a (away), along b (away)
                for (pa, da) in [(wa.centerStart, wa.direction), (wa.centerEnd, wa.direction * -1)] {
                    for (pb, db) in [(wb.centerStart, wb.direction), (wb.centerEnd, wb.direction * -1)] where pa.distance(to: pb) <= tol {
                        corner = ((pa + pb) / 2, da, db)
                    }
                }
                guard let (c, da, db) = corner, abs(da.cross(db)) > 0.17 else { continue }   // > ~10°
                let probe = c + (da + db).normalized * (tol * 1.5)
                let convex = inside(probe, a.level)
                let h = min(wa.height, wb.height) * m
                add(convex ? "corner" : "corner-reentrant", [a.id, b.id], h, c)
            }
        }
        for (el, w) in extWalls {
            let mid = (w.centerStart + w.centerEnd) / 2
            if el.level == lowest { add("ground-floor", [el.id], w.length * m, mid) }
            // Roof / eaves: walls of the top level, or walls under a roof of the same level.
            let roofOver = doc.elements.contains { e in
                guard case .roof(let r) = e.geometry, e.level == el.level || e.level == el.level + 1 else { return false }
                return GeometryOps.pointInPolygon(mid, r.boundary) || GeometryOps.distance(from: mid, toPolyline: r.boundary + [r.boundary[0]]) <= w.thickness + r.overhang
            }
            if el.level == highest || roofOver { add("roof-eaves", [el.id], w.length * m, mid) }
        }
        // Slab edges along exterior walls (intermediate floors) and balconies.
        for s in doc.elements {
            guard case .slab(let sl) = s.geometry, sl.boundary.count >= 3 else { continue }
            let kind = s.props["kind"] ?? ""
            guard kind.isEmpty || kind == "floor" || kind == "balcony" else { continue }
            for (el, w) in extWalls {
                // The slab is the floor of its level: it meets that level's exterior walls at their base.
                guard el.level == s.level else { continue }
                // Length of the wall axis covered by the slab outline (sampled).
                let n = 40
                var covered = 0.0
                var outsideLen = 0.0
                let a = w.centerStart, b = w.centerEnd
                let perp = w.direction.perp * (w.thickness / 2 + 50 / doc.units.mm)
                for k in 0..<n {
                    let t = (Double(k) + 0.5) / Double(n)
                    let p = a + (b - a) * t
                    let onSlab = GeometryOps.pointInPolygon(p, sl.boundary) || GeometryOps.distance(from: p, toPolyline: sl.boundary + [sl.boundary[0]]) <= w.thickness / 2 + 1 / doc.units.mm
                    guard onSlab else { continue }
                    covered += w.length / Double(n)
                    // Slab on both sides of the wall face: projecting outside the building.
                    let outer = inside(p + perp, el.level) ? p - perp : p + perp
                    if GeometryOps.pointInPolygon(outer, sl.boundary) { outsideLen += w.length / Double(n) }
                }
                if outsideLen > 1e-9 { add("balcony", [s.id, el.id], outsideLen * m, (a + b) / 2) }
                let edge = covered - outsideLen
                if edge > 1e-9, kind != "balcony", s.level != lowest { add("intermediate-floor", [s.id, el.id], edge * m, (a + b) / 2) }
            }
        }
        // Reveals of openings in exterior walls.
        let extIDs = Set(extWalls.map(\.el.id))
        for el in doc.elements {
            guard case .opening(let o) = el.geometry, o.kind != .opening, extIDs.contains(o.hostWall), let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else { continue }
            let at = w.centerStart + w.direction * o.offset
            add(o.kind == .door ? "door-reveal" : "window-reveal", [el.id, host.id], 2 * (o.width + o.height) * m, at)
        }
        // Columns inside exterior walls.
        for el in doc.elements {
            guard case .column(let c) = el.geometry else { continue }
            if let (wel, _) = extWalls.first(where: { $0.el.level == el.level && Thermal.segDist(c.position, $0.w.centerStart, $0.w.centerEnd) <= $0.w.thickness / 2 + max(c.width, c.depth) / 2 }) {
                add("column", [el.id, wel.id], c.height * m, c.position)
            }
        }
        if usesNumericPsi(doc) {
            var cache: [String: Double] = [:]
            for i in out.indices where doc.variable("PSI:" + out[i].kind).flatMap(Double.init) == nil {
                if let v = numericPsi(out[i], doc: doc, cache: &cache) { out[i].psi = v }
            }
        }
        return out
    }

    /// True when the drawing variable PSIMETHOD asks for EN ISO 10211 numerical ψ values.
    public static func usesNumericPsi(_ doc: ArchiDocument) -> Bool {
        let v = (doc.variable("PSIMETHOD") ?? "").uppercased().replacingOccurrences(of: " ", with: "")
        return v == "ISO10211" || v == "NUMERIC" || v == "2D"
    }

    /// Wall build-up (outside → inside, plies of the wall type) for the numerical junction models.
    public static func layers(_ el: BIMElement, doc: ArchiDocument) -> [JunctionPsi.Layer]? {
        guard let c = Thermal.uValue(el, doc: doc, component: "wall"), !c.layers.isEmpty else { return nil }
        let l = c.layers.filter { $0.thickness > 0 }.map { JunctionPsi.Layer($0.thickness, $0.lambda ?? 1.0) }
        return l.isEmpty ? nil : l
    }

    /// External-dimension ψ of a detected junction from a 2D EN ISO 10211 calculation (corners, floor edges,
    /// balconies); nil for junction kinds without a numerical model.
    public static func numericPsi(_ b: ThermalBridge, doc: ArchiDocument, cache: inout [String: Double]) -> Double? {
        let mm = doc.units.mm / 1000
        func key(_ l: [JunctionPsi.Layer], _ extra: String) -> String { b.kind + "|" + extra + "|" + l.map { "\($0.thickness):\($0.lambda)" }.joined(separator: ",") }
        switch b.kind {
        case "corner", "corner-reentrant":
            guard let w = b.elements.first.flatMap({ doc.element($0) }), let l = layers(w, doc: doc) else { return nil }
            let k = key(l, "")
            if let v = cache[k] { return v }
            let v = JunctionPsi.corner(l, reentrant: b.kind == "corner-reentrant", maxCell: 0.015).psiExternal
            cache[k] = v; return v
        case "intermediate-floor", "balcony":
            guard b.elements.count >= 2, let s = doc.element(b.elements[0]), case .slab(let sg) = s.geometry,
                  let w = doc.element(b.elements[1]), let l = layers(w, doc: doc) else { return nil }
            let mat = s.material ?? "Concrete"
            let lam = ThermalLibrary.lambda(mat, doc: doc) ?? 2.0
            let ts = sg.thickness * mm
            guard ts > 0 else { return nil }
            let proj = b.kind == "balcony" ? 1.2 : 0
            let k = key(l, "\(ts):\(lam):\(proj)")
            if let v = cache[k] { return v }
            let v = JunctionPsi.floorEdge(wall: l, slabThickness: ts, slabLambda: lam, balcony: proj, maxCell: 0.015).psiExternal
            cache[k] = v; return v
        default: return nil
        }
    }

    public struct Summary { public var bridges: [ThermalBridge]; public var htb: Double; public var transmission: Double
        /// Share of the plain-element transmission loss (H_T without bridges).
        public var share: Double { transmission > 0 ? htb / transmission : 0 }
        public var byKind: [(kind: String, length: Double, h: Double)] {
            Dictionary(grouping: bridges, by: \.kind).map { (kind: $0.key, length: $0.value.reduce(0) { $0 + $1.length }, h: $0.value.reduce(0) { $0 + $1.h }) }.sorted { $0.h > $1.h }
        }
    }

    public static func summary(_ doc: ArchiDocument) -> Summary {
        let b = detect(doc)
        var o = HeatLossOptions.from(doc); o.thermalBridge = 0
        let t = HeatLoss.compute(doc, options: o).transmission
        return Summary(bridges: b, htb: b.reduce(0) { $0 + $1.h }, transmission: t)
    }
}

extension ThermalBridges {
    static var command: CommandDef {
        CommandDef("THERMALBRIDGES", aliases: ["THERMALBRIDGE", "PSIVALUES", "TBHINT"], category: "Analyze",
                   summary: "Finds geometric linear thermal bridges of the envelope (wall corners, ground and intermediate floor edges, balconies, eaves, window/door reveals, columns in exterior walls) with lengths, ψ values (PSI:<kind> overrides) and H_TB = Σψ·L; selects the elements.", modifies: false) { ed in
            let s = summary(ed.doc)
            guard !s.bridges.isEmpty else { ed.print("No exterior walls found: nothing to check."); return }
            ed.print(usesNumericPsi(ed.doc) ? "ψ of corners, floor edges and balconies: EN ISO 10211 2D calculation from the wall build-ups (PSIMETHOD)." : "ψ: EN ISO 14683 default values (set PSIMETHOD to ISO10211 for a 2D calculation from the wall build-ups).")
            ed.print("Thermal bridges: \(s.bridges.count) junction(s), H_TB = \(fmt(s.htb, 2)) W/K (\(fmt(s.share * 100, 1)) % of the plain transmission loss \(fmt(s.transmission, 1)) W/K).")
            for k in s.byKind {
                ed.print("  \(titles[k.kind] ?? k.kind): \(fmt(k.length, 2)) m × ψ \(fmt(k.length > 0 ? k.h / k.length : psi(k.kind, doc: ed.doc), 2)) = \(fmt(k.h, 2)) W/K")
            }
            if s.share > 0.15 { ed.print("Hint: thermal bridges exceed 15 % of the element losses — insulate balconies (thermal breaks) and slab edges first.") }
            ed.selection = Set(s.bridges.filter { $0.psi > 0.3 }.flatMap(\.elements)).filter { ed.doc.contains($0) }
            try await AnalysisCommands.saveCSV(ed, CSVText.make([["Kind", "Elements", "Length m", "psi W/mK", "H W/K"]] + s.bridges.map {
                [titles[$0.kind] ?? $0.kind, $0.elements.map { "#\($0)" }.joined(separator: " "), fmt($0.length, 3), fmt($0.psi, 3), fmt($0.h, 3)]
            }))
        }
    }
}
