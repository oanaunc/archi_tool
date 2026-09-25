// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// A 2D user coordinate system: origin and X-axis angle relative to the world (WCS).
/// Stored in the document variables UCSORG ("x,y") and UCSANG (degrees), so it persists in .archi files.
public struct UCSFrame: Hashable {
    public var origin: Vec2
    /// X-axis angle in radians.
    public var angle: Double
    public init(origin: Vec2 = .zero, angle: Double = 0) { self.origin = origin; self.angle = angle }
    public static let world = UCSFrame()
    public var isWorld: Bool { let a = normAngle(angle); return origin.isClose(.zero, tol: 1e-12) && min(a, 2 * .pi - a) < 1e-12 }

    /// UCS point → world point.
    public func toWorld(_ p: Vec2) -> Vec2 { origin + p.rotated(by: angle) }
    /// World point → UCS point.
    public func fromWorld(_ p: Vec2) -> Vec2 { (p - origin).rotated(by: -angle) }
    public func vectorToWorld(_ v: Vec2) -> Vec2 { v.rotated(by: angle) }

    /// Serialized as "x,y,angleDegrees".
    public var text: String { "\(fmt(origin.x, 8)),\(fmt(origin.y, 8)),\(fmt(deg(angle), 10))" }
    public init?(text: String) {
        let p = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 3 else { return nil }
        self.init(origin: Vec2(p[0], p[1]), angle: rad(p[2]))
    }

    /// Current UCS of a document (world when unset).
    public static func current(_ doc: ArchiDocument) -> UCSFrame {
        var f = UCSFrame()
        if let o = doc.variable("UCSORG") {
            let p = o.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count >= 2 { f.origin = Vec2(p[0], p[1]) }
        }
        if let a = doc.variable("UCSANG").flatMap(Double.init) { f.angle = rad(a) }
        return f
    }
    /// Makes this frame current in the document (the previous one is pushed on the UCS history).
    public func apply(to doc: inout ArchiDocument, remember: Bool = true) {
        if remember {
            var prev = (doc.variable("UCSPREV") ?? "").split(separator: ";").map(String.init)
            prev.append(UCSFrame.current(doc).text)
            if prev.count > 10 { prev.removeFirst(prev.count - 10) }
            doc.setVariable("UCSPREV", prev.joined(separator: ";"))
        }
        doc.setVariable("UCSORG", "\(fmt(origin.x, 8)),\(fmt(origin.y, 8))")
        doc.setVariable("UCSANG", fmt(deg(normAngle(angle)), 10))
    }
}

/// Context used by the input parser: drawing units (for unit-suffixed values) and the current UCS.
public struct ParseContext {
    public var units: Units
    public var ucs: UCSFrame
    public init(units: Units = .millimeters, ucs: UCSFrame = .world) { self.units = units; self.ucs = ucs }
}

/// CAL expressions with geometric functions: dist(p1;p2), ang(p1;p2), plus arithmetic and unit suffixes.
/// Points are written x,y and separated by ";" or given in brackets: dist([0,0],[3,4]).
public enum CalcFunctions {
    static func points(_ inner: String) -> [Vec2]? {
        var parts: [String]
        if inner.contains("[") {
            parts = []
            var cur = "", depth = 0
            for ch in inner {
                if ch == "[" { depth += 1; cur = ""; continue }
                if ch == "]" { depth -= 1; parts.append(cur); continue }
                if depth > 0 { cur.append(ch) }
            }
        } else { parts = inner.split(separator: ";").map(String.init) }
        let saved = InputParser.context
        InputParser.context.ucs = .world
        defer { InputParser.context = saved }
        let pts = parts.compactMap { InputParser.parsePoint($0.trimmingCharacters(in: .whitespaces), last: nil) }
        return pts.count == parts.count ? pts : nil
    }

    /// Replaces dist(...) / ang(...) calls by their values, then evaluates the arithmetic.
    public static func evaluate(_ expr: String) -> Double? {
        var s = expr.replacingOccurrences(of: " ", with: "")
        let fns = ["dist", "ang"]
        var guardN = 0
        while guardN < 100, let r = fns.compactMap({ s.range(of: $0 + "(", options: .caseInsensitive) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            guardN += 1
            var depth = 1, j = r.upperBound
            while j < s.endIndex, depth > 0 {
                if s[j] == "(" { depth += 1 } else if s[j] == ")" { depth -= 1 }
                if depth > 0 { j = s.index(after: j) }
            }
            guard j < s.endIndex else { return nil }
            let name = s[r].dropLast().lowercased()
            guard let pts = points(String(s[r.upperBound..<j])), pts.count == 2 else { return nil }
            let v = name == "dist" ? pts[0].distance(to: pts[1]) : deg(normAngle((pts[1] - pts[0]).angle))
            s.replaceSubrange(r.lowerBound...j, with: "(" + fmt(v, 12) + ")")
        }
        return CommandHelpers.evaluate(s) ?? InputParser.parseNumber(s)
    }
}
