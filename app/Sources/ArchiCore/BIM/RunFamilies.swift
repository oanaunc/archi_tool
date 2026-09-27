// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// A pipe connection point of a plumbing fixture or a duct/electrical terminal (family-local position, Z above the base).
public struct MEPConnector: Hashable {
    /// System: "DCW" (cold water), "DHW" (hot water), "SAN" (sanitary waste), "VENT", "AIR", "POWER".
    public var system: String
    public var position: Vec3
    /// Nominal diameter (mm).
    public var diameter: Double
    public init(_ system: String, _ position: Vec3, _ diameter: Double) { self.system = system; self.position = position; self.diameter = diameter }
}

/// Families that follow a path (ComponentGeom.path): pipes, conduits, ducts, cable trays and retaining walls.
/// size.x = diameter / width, size.z = height (ducts, trays, walls); `baseOffset` = pipe/duct centreline, tray bottom, wall base.
public enum RunFamilies {
    public static let ids: Set<String> = ["pipe", "conduit", "duct", "cabletray", "retaining-wall"]
    public static func isRun(_ id: String?) -> Bool { id.map { ids.contains($0) } ?? false }

    /// MEP systems (props["system"]) with their display colours: plumbing, drainage, HVAC and electrical.
    public static let systems: [(code: String, name: String, color: RGBA)] = [
        ("DCW", "Domestic Cold Water", RGBA(0.25, 0.55, 1.0)), ("DHW", "Domestic Hot Water", RGBA(1.0, 0.35, 0.3)),
        ("SAN", "Sanitary Waste", RGBA(0.65, 0.45, 0.25)), ("VENT", "Vent", RGBA(0.45, 0.8, 0.45)),
        ("RWL", "Rainwater", RGBA(0.3, 0.75, 0.85)), ("GAS", "Gas", RGBA(1.0, 0.85, 0.2)),
        ("SA", "Supply Air", RGBA(0.35, 0.65, 1.0)), ("RA", "Return Air", RGBA(0.95, 0.55, 0.75)), ("EA", "Exhaust Air", RGBA(0.75, 0.6, 0.4)),
        ("HWS", "Heating Flow", RGBA(0.95, 0.25, 0.45)), ("HWR", "Heating Return", RGBA(0.55, 0.35, 0.95)),
        ("POWER", "Power", RGBA(1.0, 0.6, 0.1)), ("DATA", "Data", RGBA(0.6, 0.5, 1.0)), ("FIRE", "Fire Protection", RGBA(0.9, 0.15, 0.15)),
    ]
    public static func systemColor(_ code: String?) -> RGBA? {
        guard let c = code else { return nil }
        return systems.first { $0.code.caseInsensitiveCompare(c) == .orderedSame }?.color
    }

    /// World-space 3D polyline of the run (z0 = level elevation + baseOffset).
    static func path3(_ g: ComponentGeom, z0: Double) -> [Vec3] {
        let w = g.worldPath
        var out: [Vec3] = []
        for (i, p) in w.enumerated() {
            let q = Vec3(p.x, p.y, z0 + g.pathHeight(i))
            if let l = out.last, l.distance(to: q) < 1e-9 { continue }
            out.append(q)
        }
        return out
    }

    /// Rotates v about unit axis k by angle a (Rodrigues).
    static func rotate(_ v: Vec3, _ k: Vec3, _ a: Double) -> Vec3 {
        v * cos(a) + k.cross(v) * sin(a) + k * (k.dot(v) * (1 - cos(a)))
    }

    /// Centreline with circular bends of radius `radius` at interior vertices (clamped to the segment lengths).
    /// Returns the polyline and the bend tangent points (fitting ends) with their tangent directions.
    static func filleted(_ pts: [Vec3], radius: Double, segments: Int = 8) -> (line: [Vec3], ends: [(Vec3, Vec3)]) {
        guard pts.count >= 3, radius > 1e-9 else { return (pts, []) }
        var out = [pts[0]]
        var ends: [(Vec3, Vec3)] = []
        for i in 1..<(pts.count - 1) {
            let p = pts[i], a = (p - pts[i - 1]).normalized, b = (pts[i + 1] - p).normalized
            let turn = acos(max(-1, min(1, a.dot(b))))
            guard turn > 1e-4, turn < Double.pi - 1e-4 else { out.append(p); continue }
            let li = p.distance(to: pts[i - 1]), lo = p.distance(to: pts[i + 1])
            let t = min(radius * tan(turn / 2), 0.45 * li, 0.45 * lo)
            let r = t / tan(turn / 2)
            let t1 = p - a * t, t2 = p + b * t
            let axis = a.cross(b).normalized
            let n1 = axis.cross(a).normalized          // from T1 towards the centre
            let c = t1 + n1 * r
            let v0 = t1 - c
            for k in 0...segments { out.append(c + rotate(v0, axis, turn * Double(k) / Double(segments))) }
            ends.append((t1, a)); ends.append((t2, b))
        }
        out.append(pts[pts.count - 1])
        return (out, ends)
    }

    static func circle(_ r: Double, _ n: Int = 16) -> [Vec2] { (0..<n).map { Vec2.polar(r, 2 * Double.pi * Double($0) / Double(n)) } }

    /// Cross-section (x across to the left of travel, y up) of a run family.
    static func section(_ id: String, _ g: ComponentGeom, unit u: Double) -> [Vec2] {
        let W = max(g.size.x, 1e-3), H = max(g.size.z, 1e-3)
        switch id {
        case "pipe", "conduit": return circle(W / 2, W > 150 * u ? 24 : 16)
        case "duct": return [Vec2(-W / 2, -H / 2), Vec2(W / 2, -H / 2), Vec2(W / 2, H / 2), Vec2(-W / 2, H / 2)]
        case "cabletray":
            let t = min(2 * u, W / 10), h = H
            return [Vec2(-W / 2, 0), Vec2(W / 2, 0), Vec2(W / 2, h), Vec2(W / 2 - t, h), Vec2(W / 2 - t, t), Vec2(-W / 2 + t, t), Vec2(-W / 2 + t, h), Vec2(-W / 2, h)]
        case "retaining-wall":
            let t = W, fw = max(0.6 * H, 2.5 * t), fd = max(0.1 * H, 0.8 * t)
            return [Vec2(-fw * 0.3, -fd), Vec2(fw * 0.7, -fd), Vec2(fw * 0.7, 0), Vec2(t / 2, 0), Vec2(t * 0.35, H), Vec2(-t * 0.35, H), Vec2(-t / 2, 0), Vec2(-fw * 0.3, 0)]
        default: return circle(W / 2)
        }
    }

    static func meshGroups(_ f: ComponentFamily, _ g: ComponentGeom, id: EntityID?, z0: Double, unit u: Double, overrides: [String: String]) -> [MeshGroup] {
        let pts = path3(g, z0: z0)
        guard pts.count >= 2 else { return [] }
        var body = MeshAcc(), fit = MeshAcc()
        let sec = section(f.id, g, unit: u)
        let W = max(g.size.x, 1e-3)
        switch f.id {
        case "pipe", "conduit":
            let fl = filleted(pts, radius: 1.5 * W)
            SweepMesh.sweep(sec, along: fl.line, into: &body)
            // Elbow fittings: sleeves at both tangent points of every bend.
            let sleeve = circle(W * 0.58, 20), len = max(W * 0.3, 10 * u)
            for (p, d) in fl.ends { fit.member(sleeve, from: p - d * (len / 2), to: p + d * (len / 2), smooth: true) }
            // Couplings every 6 m along straight runs.
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1], L = a.distance(to: b), d = (b - a) / max(L, 1e-9)
                var s = 6000 * u
                while s < L - 1500 * u { fit.member(sleeve, from: a + d * (s - len / 2), to: a + d * (s + len / 2), smooth: true); s += 6000 * u }
            }
        case "duct":
            SweepMesh.sweep(sec, along: pts, into: &body)
            // Flanges either side of every bend and at the ends.
            let H = max(g.size.z, 1e-3), fw = W / 2 + 25 * u, fh = H / 2 + 25 * u
            let flange = [Vec2(-fw, -fh), Vec2(fw, -fh), Vec2(fw, fh), Vec2(-fw, fh)]
            let hole = [Vec2(-W / 2, -H / 2), Vec2(-W / 2, H / 2), Vec2(W / 2, H / 2), Vec2(W / 2, -H / 2)]
            for i in 0..<pts.count {
                var places: [(Vec3, Vec3)] = []
                if i > 0 { let d = (pts[i] - pts[i - 1]).normalized; let back = min(W * 0.6, pts[i].distance(to: pts[i - 1]) * 0.4); places.append((pts[i] - d * back, d)) }
                if i < pts.count - 1 && i > 0 { let d = (pts[i + 1] - pts[i]).normalized; let fwd = min(W * 0.6, pts[i].distance(to: pts[i + 1]) * 0.4); places.append((pts[i] + d * fwd, d)) }
                if i == 0 { places.append((pts[0], (pts[1] - pts[0]).normalized)) }
                for (p, d) in places { fit.member(flange, holes: [hole], from: p - d * (4 * u), to: p + d * (4 * u)) }
            }
        case "cabletray":
            SweepMesh.sweep(sec, along: pts, into: &body)
        default:
            SweepMesh.sweep(sec, along: pts, into: &body)
        }
        let bodyMat: String
        switch f.id {
        case "pipe": bodyMat = "Steel"
        case "conduit", "duct", "cabletray": bodyMat = "Aluminium"
        default: bodyMat = "Concrete"
        }
        return [body.group(id, "component", overrides["material." + f.id] ?? overrides["material"] ?? bodyMat),
                fit.group(id, "component", overrides["material.fitting"] ?? "Aluminium")].compactMap { $0 }
    }

    /// Plan symbol of a run in world coordinates.
    static func symbol(_ f: ComponentFamily, _ g: ComponentGeom) -> [ComponentSymbolLine] {
        let pts2 = RG.dedupe(g.worldPath, closed: false)
        guard pts2.count >= 2 else { return [] }
        let W = max(g.size.x, 1e-3)
        var out: [ComponentSymbolLine] = []
        func add(_ p: [Vec2], closed: Bool = false, outline: Bool = true, hidden: Bool = false) { out.append(ComponentSymbolLine(points: p, closed: closed, outline: outline, hidden: hidden)) }
        switch f.id {
        case "pipe", "conduit":
            let line = filleted(pts2.map { Vec3($0.x, $0.y, 0) }, radius: 1.5 * W).line.map(\.xy)
            add(PlanRepresentation.offsetPolyline(line, W / 2)); add(PlanRepresentation.offsetPolyline(line, -W / 2))
            add(line, outline: false, hidden: true)
            for (p, d) in filleted(pts2.map { Vec3($0.x, $0.y, 0) }, radius: 1.5 * W).ends {
                let n = Vec2(-d.y, d.x).normalized * (W * 0.62)
                add([p.xy - n, p.xy + n], outline: false)
            }
        case "duct":
            add(PlanRepresentation.offsetPolyline(pts2, W / 2)); add(PlanRepresentation.offsetPolyline(pts2, -W / 2))
            add(pts2, outline: false, hidden: true)
            // Diagonal cross on each straight piece (supply duct convention).
            for i in 0..<(pts2.count - 1) {
                let a = pts2[i], b = pts2[i + 1], d = (b - a).normalized, n = d.perp * (W / 2)
                let m = (a + b) / 2, h = min(W / 2, a.distance(to: b) / 4)
                add([m - d * h - n, m + d * h + n], outline: false); add([m - d * h + n, m + d * h - n], outline: false)
            }
        case "cabletray":
            add(PlanRepresentation.offsetPolyline(pts2, W / 2)); add(PlanRepresentation.offsetPolyline(pts2, -W / 2))
            // Rungs every 300 mm.
            for i in 0..<(pts2.count - 1) {
                let a = pts2[i], b = pts2[i + 1], L = a.distance(to: b), d = (b - a) / max(L, 1e-9), n = d.perp * (W / 2)
                var s = 150.0
                while s < L { add([a + d * s - n, a + d * s + n], outline: false); s += 300 }
            }
        default: // retaining wall: stem solid, footing hidden
            let t = W, H = max(g.size.z, 1e-3), fw = max(0.6 * H, 2.5 * t)
            add(PlanRepresentation.offsetPolyline(pts2, t / 2)); add(PlanRepresentation.offsetPolyline(pts2, -t / 2))
            add(PlanRepresentation.offsetPolyline(pts2, -fw * 0.3), outline: false, hidden: true)
            add(PlanRepresentation.offsetPolyline(pts2, fw * 0.7), outline: false, hidden: true)
        }
        return out
    }

    /// Total length of the run's plan path and its 3D length.
    public static func length(_ g: ComponentGeom) -> Double {
        let p = path3(g, z0: 0)
        return zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}

/// Plumbing fixture connection points and electrical fixture families.
extension ComponentLibrary {
    /// Connection points of a family (family-local; Z above the component base).
    public static func connectors(_ f: ComponentFamily, size s: Vec3) -> [MEPConnector] {
        let W = s.x, D = s.y, H = s.z
        let back = D / 2 - 40
        switch f.id {
        case "wc": return [MEPConnector("SAN", Vec3(0, back - 60, 180), 100), MEPConnector("DCW", Vec3(-W * 0.3, back, H * 0.85), 15)]
        case "basin": return [MEPConnector("SAN", Vec3(0, back, 450), 40), MEPConnector("DCW", Vec3(-80, back, 550), 15), MEPConnector("DHW", Vec3(80, back, 550), 15)]
        case "kitchen-sink": return [MEPConnector("SAN", Vec3(0, back, 450), 50), MEPConnector("DCW", Vec3(-100, back, 550), 15), MEPConnector("DHW", Vec3(100, back, 550), 15)]
        case "bath": return [MEPConnector("SAN", Vec3(0, D / 2 - 300, 50), 40), MEPConnector("DCW", Vec3(-60, D / 2 - 30, H + 50), 15), MEPConnector("DHW", Vec3(60, D / 2 - 30, H + 50), 15)]
        case "shower": return [MEPConnector("SAN", Vec3(0, 0, 0), 50), MEPConnector("DCW", Vec3(W / 2 - 120, D / 2 - 20, 1000), 15), MEPConnector("DHW", Vec3(W / 2 - 40, D / 2 - 20, 1000), 15)]
        case "washer": return [MEPConnector("SAN", Vec3(W / 4, back, 600), 40), MEPConnector("DCW", Vec3(-W / 4, back, 900), 15), MEPConnector("POWER", Vec3(0, back, 300), 0)]
        case "fridge", "range": return [MEPConnector("POWER", Vec3(0, back, 300), 0)]
        case "outlet", "switch", "light-ceiling", "light-wall", "panel", "smoke-detector": return [MEPConnector("POWER", Vec3(0, 0, 0), 0)]
        case let id where terminalIDs.contains(id): return terminalConnectors(id, W: W, D: D, H: H)
        default: return []
        }
    }

    /// World-space connectors of an instance (z0 = level elevation + base offset).
    public static func worldConnectors(_ f: ComponentFamily, _ g: ComponentGeom, z0: Double) -> [MEPConnector] {
        let c = cos(g.rotation), s = sin(g.rotation)
        return connectors(f, size: g.size).map { k in
            var w = k
            w.position = Vec3(g.position.x + k.position.x * c - k.position.y * s, g.position.y + k.position.x * s + k.position.y * c, z0 + k.position.z)
            return w
        }
    }

    /// 3D parts of electrical families (family-local).
    static func electricalParts(_ id: String, _ p: inout Parts, W: Double, D: Double, H: Double) {
        let x0 = -W / 2, x1 = W / 2, y0 = -D / 2, y1 = D / 2
        switch id {
        case "outlet", "switch":
            p.box("Laminate", x0, x1, y1 - 12, y1, 0, H)
            if id == "outlet" { for dx in [-W * 0.18, W * 0.18] { p.box("Rubber", dx - 4, dx + 4, y1 - 14, y1 - 12, H * 0.35, H * 0.65) } }
            else { p.box("Laminate", -W * 0.2, W * 0.2, y1 - 20, y1 - 12, H * 0.3, H * 0.7) }
        case "light-ceiling":
            p.ellipsePrism("Aluminium", .zero, W / 2, D / 2, H * 0.7, H)
            p.ellipsePrism("Glass", .zero, W * 0.45, D * 0.45, 0, H * 0.7)
        case "light-wall":
            p.box("Aluminium", x0, x1, y1 - 20, y1, 0, H)
            p.ellipsePrism("Glass", Vec2(0, y1 - D / 2), W * 0.4, D * 0.45, H * 0.2, H * 0.8)
        case "panel":
            p.box("Steel", x0, x1, y0 + 10, y1, 0, H)
            p.box("Aluminium", x0 + 10, x1 - 10, y0, y0 + 10, 10, H - 10)
            p.box("Rubber", x1 - 50, x1 - 30, y0 - 15, y0, H * 0.45, H * 0.55)
        case "smoke-detector":
            p.ellipsePrism("Laminate", .zero, W / 2, D / 2, 0, H)
        default: break
        }
    }

    /// Plan symbols of electrical families (IEC/ANSI style).
    static func electricalSymbol(_ id: String, W: Double, D: Double) -> [ComponentSymbolLine] {
        var out: [ComponentSymbolLine] = []
        func add(_ pts: [Vec2], closed: Bool = false, outline: Bool = true) { out.append(ComponentSymbolLine(points: pts, closed: closed, outline: outline, hidden: false)) }
        let r = max(min(W, 400) * 0.5, 60)
        switch id {
        case "outlet":
            // Duplex receptacle: circle with two parallel strokes, tied to the wall (+Y side).
            add(RG.circle(.zero, r, segments: 24), closed: true)
            add([Vec2(-r * 0.35, -r * 1.3), Vec2(-r * 0.35, r * 1.3)], outline: false); add([Vec2(r * 0.35, -r * 1.3), Vec2(r * 0.35, r * 1.3)], outline: false)
            add([Vec2(0, r), Vec2(0, D / 2)], outline: false)
        case "switch":
            // Single-pole switch: small circle with a lever stroke.
            add(RG.circle(.zero, r * 0.45, segments: 16), closed: true)
            add([Vec2(r * 0.32, -r * 0.32), Vec2(r * 1.3, -r * 1.3), Vec2(r * 1.6, -r * 1.0)], outline: false)
        case "light-ceiling":
            let R = max(W, D) / 2
            add(RG.circle(.zero, R, segments: 32), closed: true)
            add([Vec2(-R * 0.707, -R * 0.707), Vec2(R * 0.707, R * 0.707)], outline: false); add([Vec2(-R * 0.707, R * 0.707), Vec2(R * 0.707, -R * 0.707)], outline: false)
        case "light-wall":
            let R = W / 2
            var arc: [Vec2] = [Vec2(-R, D / 2)]
            for k in stride(from: 12, through: 0, by: -1) { let a: Double = Double.pi + Double.pi * Double(k) / 12; arc.append(Vec2.polar(R, a) + Vec2(0, D / 2)) }
            arc.append(Vec2(R, D / 2))
            add(arc, closed: true)
            add([Vec2(-R * 0.5, D / 2 - R * 0.8), Vec2(R * 0.5, D / 2 - R * 0.1)], outline: false); add([Vec2(-R * 0.5, D / 2 - R * 0.1), Vec2(R * 0.5, D / 2 - R * 0.8)], outline: false)
        case "panel":
            add([Vec2(-W / 2, -D / 2), Vec2(W / 2, -D / 2), Vec2(W / 2, D / 2), Vec2(-W / 2, D / 2)], closed: true)
            add([Vec2(-W / 2, -D / 2), Vec2(W / 2, D / 2)], outline: false)
            add([Vec2(-W / 2, D / 2 - D * 0.35), Vec2(W / 2 - W * 0.7, D / 2)], outline: false)
        case "smoke-detector":
            add(ComponentLibrary.ellipse(.zero, W / 2, D / 2, segments: 24), closed: true)
            add(ComponentLibrary.ellipse(.zero, W * 0.18, D * 0.18, segments: 12), closed: true, outline: false)
        default: break
        }
        return out
    }
}

/// Parametric trusses (families "truss-pratt", "truss-howe", "truss-warren", "truss-fink"): span along local X,
/// height Z, member width = size.y.
public enum Trusses {
    public static let kinds = ["pratt", "howe", "warren", "fink"]

    /// Members as (start, end) in the truss plane: x along the span from −span/2, z up from the bottom chord.
    public static func members(kind: String, span L: Double, height H: Double, panels: Int? = nil) -> [(Vec2, Vec2)] {
        guard L > 1e-9, H > 1e-9 else { return [] }
        let x0 = -L / 2
        func P(_ x: Double, _ z: Double) -> Vec2 { Vec2(x0 + x, z) }
        var n = panels ?? max(2, Int((L / max(H, 1e-9)).rounded()))
        if kind != "warren" && n % 2 == 1 { n += 1 }
        n = max(n, 2)
        let dx = L / Double(n)
        var out: [(Vec2, Vec2)] = []
        switch kind {
        case "fink":
            // Triangular roof truss: rafters, tie, and a W web.
            let a = P(0, 0), b = P(L, 0), apex = P(L / 2, H)
            out = [(a, apex), (apex, b), (a, b)]
            let q1 = P(L / 3, 0), q2 = P(2 * L / 3, 0), r1 = P(L / 4, H / 2), r2 = P(3 * L / 4, H / 2)
            out += [(q1, r1), (q1, apex), (q2, apex), (q2, r2)]
        case "warren":
            out = [(P(0, 0), P(L, 0)), (P(0, H), P(L, H)), (P(0, 0), P(0, H)), (P(L, 0), P(L, H))]
            // Diagonals alternating up/down.
            for i in 0..<n {
                let xa = Double(i) * dx, xb = xa + dx
                out.append(i % 2 == 0 ? (P(xa, 0), P(xb, H)) : (P(xa, H), P(xb, 0)))
            }
        default: // pratt / howe: verticals at every panel point, diagonals sloping towards (Pratt) or away from (Howe) the centre
            out = [(P(0, 0), P(L, 0)), (P(0, H), P(L, H))]
            for i in 0...n { out.append((P(Double(i) * dx, 0), P(Double(i) * dx, H))) }
            for i in 0..<n {
                let xa = Double(i) * dx, xb = xa + dx
                let leftHalf = Double(i) < Double(n) / 2
                let towardCentreDown = kind == "pratt"
                // Pratt: diagonals slope down towards the centre (tension); Howe: up towards the centre (compression).
                if leftHalf == towardCentreDown { out.append((P(xa, H), P(xb, 0))) } else { out.append((P(xa, 0), P(xb, H))) }
            }
        }
        return out
    }

    static func kind(of familyID: String) -> String? {
        guard familyID.hasPrefix("truss-") else { return nil }
        let k = String(familyID.dropFirst(6))
        return kinds.contains(k) ? k : nil
    }

    static func parts(_ kind: String, _ p: inout ComponentLibrary.Parts, W: Double, D: Double, H: Double) {
        let t = max(min(D, H * 0.2), 1)
        let sec = [Vec2(-D / 2, -t / 2), Vec2(D / 2, -t / 2), Vec2(D / 2, t / 2), Vec2(-D / 2, t / 2)]
        // Keep members inside the envelope: chord centrelines inset by half the member depth.
        let inset = max(t, D) / 2
        for (a, b) in members(kind: kind, span: W - 2 * inset, height: max(H - 2 * inset, 1e-6)) {
            let A = Vec3(a.x, 0, a.y + inset), B = Vec3(b.x, 0, b.y + inset)
            p.acc("Wood") { $0.member(sec, from: A, to: B) }
        }
    }
}
