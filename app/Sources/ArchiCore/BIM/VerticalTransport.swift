// Oanarina Archi Tool — GPL-3.0-or-later
// Escalators (BIM-074): layout from rise / inclination / step width, EN 115-1 style rule checks, 3D and plan symbol
// (family "escalator" in ComponentLibrary) and the floor opening above the flight.
import Foundation

public enum Escalators {
    /// Height of the plan cut plane used by the escalator symbol (parts above are dashed beyond a cut line).
    public static let planCutHeight = 1200.0
    /// Nominal step widths (mm).
    public static let stepWidths: [Double] = [600, 800, 1000]
    /// Overall width = step width + balustrades and decks.
    public static let sideAllowance = 600.0

    /// Local section of an escalator family instance (travel +Y, bottom landing at −length/2, rise to +length/2).
    public struct Section {
        public var width: Double, length: Double, rise: Double
        public init(width: Double, length: Double, rise: Double) { self.width = width; self.length = length; self.rise = rise }
        public var stepWidth: Double { max(width - Escalators.sideAllowance, width * 0.5) }
        /// Horizontal landing (flat steps + comb) at each end.
        public var landing: Double { min(Escalators.defaultLanding, length * 0.35) }
        public var run: Double { max(length - 2 * landing, 1) }
        public var trussDepth: Double { 1000 }
        public var y0: Double { -length / 2 }
        public var y1: Double { length / 2 }
        public var inclination: Double { atan2(rise, run) }
        /// Step line (landing, incline, landing) offset vertically by dz, as a (y, z) polyline.
        public func stepLine(dz: Double) -> [(x: Double, z: Double)] {
            [(y0, dz), (y0 + landing, dz), (y1 - landing, rise + dz), (y1, rise + dz)]
        }
        public var stepCount: Int { max(1, Int((rise / 200).rounded(.up))) }
        /// Riser-first sawtooth from the foot of the incline to the top landing (stays on or above the step line).
        public func sawtooth() -> [(x: Double, z: Double)] {
            let n = stepCount, g = run / Double(n), r = rise / Double(n), ys = y0 + landing
            var out: [(x: Double, z: Double)] = []
            for k in 0..<n {
                out.append((ys + Double(k) * g, Double(k) * r))
                out.append((ys + Double(k) * g, Double(k + 1) * r))
            }
            out.append((y1 - landing, rise)); out.append((y1, rise))
            return Section.clean(out)
        }
        /// Underside of the truss (trussDepth below the step line, never below the level), from the top end back to `yEnd`.
        public func underside(to yEnd: Double) -> [(x: Double, z: Double)] {
            let zt = max(rise - trussDepth, 0)
            var out: [(x: Double, z: Double)] = [(y1, zt), (y1 - landing, zt)]
            if rise > trussDepth { out.append((y0 + landing + run * trussDepth / rise, 0)) }
            out.append((yEnd, 0))
            return Section.clean(out)
        }
        static func clean(_ pts: [(x: Double, z: Double)]) -> [(x: Double, z: Double)] {
            var c: [(x: Double, z: Double)] = []
            for p in pts where !(c.last.map { abs($0.x - p.x) < 1e-9 && abs($0.z - p.z) < 1e-9 } ?? false) { c.append(p) }
            return c
        }
        /// Plan Y where the step line reaches height h.
        public func y(atHeight h: Double) -> Double {
            guard rise > 1e-9 else { return y1 }
            if h <= 0 { return y0 + landing }
            if h >= rise { return y1 }
            return y0 + landing + run * h / rise
        }
        /// Plan tread lines: incline steps plus flat steps on both landings (400 mm apart).
        public func treadLines() -> [Double] {
            var out: [Double] = []
            let n = stepCount, g = run / Double(n)
            for k in 0...n { out.append(y0 + landing + Double(k) * g) }
            var y = y0 + landing - 400
            while y > y0 + 200 { out.append(y); y -= 400 }
            y = y1 - landing + 400
            while y < y1 - 200 { out.append(y); y += 400 }
            return out.sorted()
        }
    }

    public static let defaultLanding = 2000.0

    /// Horizontal length of an escalator: incline run plus two landings.
    public static func length(rise: Double, angleDeg: Double, landing: Double = defaultLanding) -> Double {
        rise / tan(max(angleDeg, 1) * .pi / 180) + 2 * landing
    }

    /// Rule check (EN 115-1 style). Units mm, speed m/s. Returns violations (empty = compliant).
    public static func check(rise: Double, angleDeg: Double, stepWidth: Double, speed: Double = 0.5, landing: Double = defaultLanding) -> [String] {
        var out: [String] = []
        if rise <= 0 { out.append("The rise must be positive.") }
        if angleDeg > 35 + 1e-9 { out.append("Inclination \(fmt(angleDeg))° exceeds 35°.") }
        else if angleDeg > 30 + 1e-9 {
            if rise > 6000 + 1e-9 { out.append("Inclination above 30° is only allowed for rises up to 6 m (rise \(fmt(rise / 1000, 2)) m).") }
            if speed > 0.5 + 1e-9 { out.append("Inclination above 30° requires a speed of at most 0.5 m/s.") }
        }
        if stepWidth < 580 - 1e-9 || stepWidth > 1100 + 1e-9 { out.append("Step width \(fmt(stepWidth)) mm is outside 580–1100 mm.") }
        let maxSpeed = angleDeg > 30 + 1e-9 ? 0.5 : 0.75
        if speed > maxSpeed + 1e-9 { out.append("Speed \(fmt(speed, 2)) m/s exceeds \(fmt(maxSpeed, 2)) m/s.") }
        // Flat steps at the landings: 0.8 m (≤ 0.5 m/s and rise ≤ 6 m), otherwise 1.2 m; plus ~0.4 m comb/deck.
        let flat = (speed <= 0.5 + 1e-9 && rise <= 6000 + 1e-9) ? 800.0 : 1200.0
        if landing - 400 < flat - 1e-9 { out.append("Landing \(fmt(landing)) mm leaves less than \(fmt(flat)) mm of flat steps.") }
        return out
    }

    /// Places an escalator from `start` (bottom comb) travelling towards `direction` (radians), rising `rise` to the
    /// level above; cuts an opening in the upper floor over the flight. Returns the component id and the shaft id.
    @discardableResult
    public static func place(_ doc: inout ArchiDocument, start: Vec2, direction: Double, rise: Double, angleDeg: Double, stepWidth: Double,
                             level: Int, topLevel: Int?, speed: Double = 0.5) -> (escalator: EntityID, opening: EntityID?) {
        let len = length(rise: rise, angleDeg: angleDeg)
        let w = stepWidth + sideAllowance
        let dir = Vec2.polar(1, direction)
        let centre = start + dir * (len / 2)
        var g = ComponentGeom(category: "Vertical Circulation", position: centre, rotation: direction - .pi / 2, size: Vec3(w, len, rise), family: "escalator")
        g.baseOffset = 0
        let id = doc.addElement(.component(g), level: level, material: "Steel", name: "Escalator")
        let issues = check(rise: rise, angleDeg: angleDeg, stepWidth: stepWidth, speed: speed)
        if let i = doc.elementIndex(id) {
            doc.elements[i].props["escalatorAngle"] = fmt(angleDeg, 3)
            doc.elements[i].props["escalatorSpeed"] = fmt(speed, 3)
            doc.elements[i].props["escalatorStepWidth"] = fmt(stepWidth, 3)
            doc.elements[i].props["escalatorCheck"] = issues.isEmpty ? "OK" : issues.joined(separator: " ")
        }
        var shaft: EntityID?
        if let t = topLevel {
            // Floor opening: from where the headroom (2.3 m + 0.3 m slab) is lost, to the top of the incline.
            let s = Section(width: w, length: len, rise: rise)
            let ya = s.y(atHeight: max(0, rise - 2600)), yb = s.y1 - s.landing
            let tr = Transform2D.translation(centre) * Transform2D.rotation(direction - .pi / 2)
            let rect = [Vec2(-w / 2, ya), Vec2(w / 2, ya), Vec2(w / 2, yb), Vec2(-w / 2, yb)].map(tr.apply)
            shaft = Shafts.add(rect, base: t, top: t, doc: &doc)
            if let si = doc.entityIndex(shaft!) { doc.entities[si].props["escalator"] = "\(id)" }
        }
        return (id, shaft)
    }

    /// Re-checks an escalator element (size drives the geometry; stored angle/speed/step width).
    public static func check(_ el: BIMElement) -> [String]? {
        guard case .component(let g) = el.geometry, g.family == "escalator" else { return nil }
        let s = Section(width: g.size.x, length: g.size.y, rise: g.size.z)
        return check(rise: g.size.z, angleDeg: s.inclination * 180 / .pi, stepWidth: s.stepWidth,
                     speed: el.props["escalatorSpeed"].flatMap(Double.init) ?? 0.5, landing: s.landing)
    }
}
