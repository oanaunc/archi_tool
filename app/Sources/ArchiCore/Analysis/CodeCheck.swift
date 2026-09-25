// Oanarina Archi Tool — GPL-3.0-or-later
// Configurable building-code checks (rules in JSON): room areas and ceiling heights, window-to-floor ratio,
// stair risers/treads/width and the step formula 2R+T, ramp gradient, door widths. Each issue has element ids and a
// zoom box (the same ModelIssue as CHECKMODEL).
import Foundation

public struct CodeRules: Codable, Hashable {
    public struct RoomRule: Codable, Hashable {
        /// Case-insensitive substring of the room name ("bed", "kitchen"); "*" = all rooms.
        public var match: String
        public var minArea: Double?
        public var minWidth: Double?
        public var minHeight: Double?
        public var minWindowToFloor: Double?
        public init(match: String, minArea: Double? = nil, minWidth: Double? = nil, minHeight: Double? = nil, minWindowToFloor: Double? = nil) {
            self.match = match; self.minArea = minArea; self.minWidth = minWidth; self.minHeight = minHeight; self.minWindowToFloor = minWindowToFloor
        }
    }
    public struct StairRule: Codable, Hashable {
        /// Millimetres.
        public var maxRiser: Double? = 190
        public var minRiser: Double? = 100
        public var minTread: Double? = 250
        public var maxTread: Double? = 400
        /// Blondel step formula range for 2·riser + tread (mm).
        public var stepFormulaMin: Double? = 590
        public var stepFormulaMax: Double? = 660
        public var minWidth: Double? = 800
        public var maxRisersPerFlight: Int? = 18
        public init() {}
    }
    public var name: String = "Default rules"
    /// Applies to every room (m²).
    public var minRoomArea: Double? = 4
    /// Room height (mm).
    public var minCeilingHeight: Double? = 2400
    /// Glazed area / floor area for habitable rooms.
    public var minWindowToFloor: Double? = 0.125
    /// Room names exempt from window checks (substring).
    public var noWindowRooms: [String] = ["bath", "wc", "toilet", "storage", "store", "closet", "corridor", "hall", "stair", "garage", "technical", "utility", "pantry", "shaft"]
    public var rooms: [RoomRule] = [RoomRule(match: "bed", minArea: 8), RoomRule(match: "living", minArea: 16)]
    public var stair: StairRule? = StairRule()
    /// rise/run (1/12 = 0.0833).
    public var maxRampGradient: Double? = 1.0 / 12
    /// Clear door width (mm).
    public var minDoorWidth: Double? = 800
    public init() {}

    enum K: String, CodingKey { case name, minRoomArea, minCeilingHeight, minWindowToFloor, noWindowRooms, rooms, stair, maxRampGradient, minDoorWidth }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        let def = CodeRules()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? def.name
        minRoomArea = try c.decodeIfPresent(Double.self, forKey: .minRoomArea)
        minCeilingHeight = try c.decodeIfPresent(Double.self, forKey: .minCeilingHeight)
        minWindowToFloor = try c.decodeIfPresent(Double.self, forKey: .minWindowToFloor)
        noWindowRooms = try c.decodeIfPresent([String].self, forKey: .noWindowRooms) ?? def.noWindowRooms
        rooms = try c.decodeIfPresent([RoomRule].self, forKey: .rooms) ?? []
        stair = try c.decodeIfPresent(StairRule.self, forKey: .stair)
        maxRampGradient = try c.decodeIfPresent(Double.self, forKey: .maxRampGradient)
        minDoorWidth = try c.decodeIfPresent(Double.self, forKey: .minDoorWidth)
    }

    public enum RulesError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid code rules: \(m)" }; return nil }
    }
    /// Rules from JSON (missing keys = rule off, except the exemption list).
    public static func fromJSON(_ text: String) throws -> CodeRules {
        do { return try JSONDecoder().decode(CodeRules.self, from: Data(text.utf8)) }
        catch { throw RulesError.invalid((error as? DecodingError).map { "\($0)" } ?? error.localizedDescription) }
    }
    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
    /// Rules stored in the drawing (variable CODERULES, JSON), else the defaults.
    public static func from(_ doc: ArchiDocument) -> CodeRules {
        if let t = doc.variable("CODERULES"), let r = try? fromJSON(t) { return r }
        return CodeRules()
    }
}

extension CodeRules.StairRule {
    enum K: String, CodingKey { case maxRiser, minRiser, minTread, maxTread, stepFormulaMin, stepFormulaMax, minWidth, maxRisersPerFlight }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        self.init()
        maxRiser = try c.decodeIfPresent(Double.self, forKey: .maxRiser); minRiser = try c.decodeIfPresent(Double.self, forKey: .minRiser)
        minTread = try c.decodeIfPresent(Double.self, forKey: .minTread); maxTread = try c.decodeIfPresent(Double.self, forKey: .maxTread)
        stepFormulaMin = try c.decodeIfPresent(Double.self, forKey: .stepFormulaMin); stepFormulaMax = try c.decodeIfPresent(Double.self, forKey: .stepFormulaMax)
        minWidth = try c.decodeIfPresent(Double.self, forKey: .minWidth); maxRisersPerFlight = try c.decodeIfPresent(Int.self, forKey: .maxRisersPerFlight)
    }
}

public enum CodeCheck {
    public static func check(_ doc: ArchiDocument, rules r: CodeRules = CodeRules()) -> [ModelIssue] {
        var out: [ModelIssue] = []
        let k = doc.units.mm           // drawing units → mm
        let u = k / 1000               // → m
        func box(_ pts: [Vec2]) -> BBox2 { let b = BBox2(points: pts); return b.isEmpty ? b : b.expanded(by: max(b.width, b.height) * 0.1 + 300 / k) }
        func issue(_ s: IssueSeverity, _ c: String, _ m: String, _ ids: [EntityID], _ pts: [Vec2]) { out.append(ModelIssue(severity: s, code: c, message: m, ids: ids, bounds: box(pts))) }
        func mm(_ v: Double) -> String { fmt(v, 0) + " mm" }

        for el in doc.elements {
            switch el.geometry {
            case .space(let s):
                guard el.props["areaScheme"] == nil, s.boundary.count >= 3 else { continue }
                let name = s.name.lowercased()
                let label = (s.number.isEmpty ? "" : s.number + " ") + s.name
                let area = abs(GeometryOps.signedArea(s.boundary)) * u * u
                let applicable = r.rooms.filter { $0.match == "*" || name.contains($0.match.lowercased()) }
                // Area
                var minA = r.minRoomArea
                for rr in applicable { if let a = rr.minArea { minA = max(minA ?? 0, a) } }
                if let a = minA, area + 1e-9 < a { issue(.error, "CODE-ROOM-AREA", "Room \(label) is \(fmt(area, 2)) m², below the minimum \(fmt(a, 2)) m²", [el.id], s.boundary) }
                // Height
                var minH = r.minCeilingHeight
                for rr in applicable { if let h = rr.minHeight { minH = max(minH ?? 0, h) } }
                if let h = minH, s.height * k + 1e-6 < h { issue(.error, "CODE-ROOM-HEIGHT", "Room \(label) is \(mm(s.height * k)) high, below \(mm(h))", [el.id], s.boundary) }
                // Width: smallest dimension of the minimum-area bounding rectangle (rotating calipers over the hull).
                if let w = applicable.compactMap(\.minWidth).max() {
                    let width = minWidth(s.boundary) * k
                    if width + 1e-6 < w { issue(.warning, "CODE-ROOM-WIDTH", "Room \(label) is \(mm(width)) wide, below \(mm(w))", [el.id], s.boundary) }
                }
                // Window-to-floor ratio
                let exempt = r.noWindowRooms.contains { !$0.isEmpty && name.contains($0.lowercased()) }
                var minWF = exempt ? nil : r.minWindowToFloor
                for rr in applicable { if let v = rr.minWindowToFloor { minWF = max(minWF ?? 0, v) } }
                if let wf = minWF, area > 0 {
                    let wins = RoomOpenings.windows(of: el, doc: doc)
                    let ratio = wins.reduce(0) { $0 + $1.glazed } / area
                    if ratio + 1e-9 < wf {
                        issue(.warning, "CODE-DAYLIGHT", "Room \(label): glazing is \(fmt(ratio * 100, 1))% of the floor area, below \(fmt(wf * 100, 1))%", [el.id] + wins.map(\.id), s.boundary)
                    }
                }
            case .stair(let st):
                guard let sr = r.stair else { continue }
                let riser = st.riserHeight * k, tread = st.treadDepth * k, width = st.width * k
                let pts = ModelChecker.elementPoints(el, doc)
                if let v = sr.maxRiser, riser > v + 1e-6 { issue(.error, "CODE-STAIR-RISER", "Stair riser \(mm(riser)) exceeds \(mm(v))", [el.id], pts) }
                if let v = sr.minRiser, riser + 1e-6 < v { issue(.warning, "CODE-STAIR-RISER", "Stair riser \(mm(riser)) is below \(mm(v))", [el.id], pts) }
                if let v = sr.minTread, tread + 1e-6 < v { issue(.error, "CODE-STAIR-TREAD", "Stair tread \(mm(tread)) is below \(mm(v))", [el.id], pts) }
                if let v = sr.maxTread, tread > v + 1e-6 { issue(.warning, "CODE-STAIR-TREAD", "Stair tread \(mm(tread)) exceeds \(mm(v))", [el.id], pts) }
                let f = 2 * riser + tread
                if let lo = sr.stepFormulaMin, let hi = sr.stepFormulaMax, f + 1e-6 < lo || f > hi + 1e-6 {
                    issue(.warning, "CODE-STAIR-FORMULA", "2R + T = \(mm(f)) is outside \(fmt(lo, 0))–\(mm(hi))", [el.id], pts)
                }
                if let v = sr.minWidth, width + 1e-6 < v { issue(.error, "CODE-STAIR-WIDTH", "Stair width \(mm(width)) is below \(mm(v))", [el.id], pts) }
                if let v = sr.maxRisersPerFlight {
                    let flight = st.landingAt.map { max($0, st.riserCount - $0) } ?? (st.kind == .straight ? st.riserCount : (st.riserCount + 1) / 2)
                    if flight > v { issue(.warning, "CODE-STAIR-FLIGHT", "A flight has \(flight) risers (more than \(v)); add a landing", [el.id], pts) }
                }
            case .slab(let s):
                guard el.props["kind"] == "ramp", s.isSloped, let g = r.maxRampGradient else { continue }
                let grad = tan(rad(abs(s.slope)))
                if grad > g + 1e-9 { issue(.error, "CODE-RAMP-GRADIENT", "Ramp gradient 1:\(fmt(1 / grad, 1)) (\(fmt(grad * 100, 1))%) is steeper than 1:\(fmt(1 / g, 1))", [el.id], s.boundary) }
            case .opening(let o):
                guard o.kind == .door, let v = r.minDoorWidth else { continue }
                let clear = (o.width - 2 * o.frameWidth) * k
                if clear + 1e-6 < v { issue(.warning, "CODE-DOOR-WIDTH", "Door clear width \(mm(clear)) is below \(mm(v))", [el.id], ModelChecker.elementPoints(el, doc)) }
            default: continue
            }
        }
        return out.sorted { ($0.severity, $0.code, $0.ids.first ?? 0) < ($1.severity, $1.code, $1.ids.first ?? 0) }
    }

    /// Width of the minimum-area enclosing rectangle (rotating calipers over the convex hull).
    public static func minWidth(_ pts: [Vec2]) -> Double {
        let h = Thermal.convexHull(pts)
        guard h.count >= 3 else { return 0 }
        var best = Double.infinity, bestArea = Double.infinity
        for i in 0..<h.count {
            let d = (h[(i + 1) % h.count] - h[i]).normalized
            guard d.length > 0.5 else { continue }
            let n = d.perp
            let xs = h.map { $0.dot(d) }, ys = h.map { $0.dot(n) }
            let w = xs.max()! - xs.min()!, hh = ys.max()! - ys.min()!
            if w * hh < bestArea { bestArea = w * hh; best = min(w, hh) }
        }
        return best
    }
}
