// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Parses command-line tokens: coordinates (x,y  @dx,dy  @d<angle  d<angle), numbers, keywords, selections (#12,#13).
public enum InputParser {
    public enum ParseError: Error { case message(String) }

    public static func parse(_ raw: String, request: InputRequest, lastPoint: Vec2?, cursor: Vec2?, ortho: Bool) -> Result<CommandInput, ParseFailure> {
        let token = raw.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return .success(.enter) }
        let k = request.kinds

        // Keywords: full word, the capitalized shortcut, or unique prefix.
        if !request.keywords.isEmpty, let kw = matchKeyword(token, request.keywords) { return .success(.keyword(kw)) }

        if k.contains(.selection) || k.contains(.entity) {
            let lower = token.lowercased()
            if ["all", "a"].contains(lower), request.keywords.contains("All") { return .success(.keyword("All")) }
            let ids = token.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }
            if !ids.isEmpty && token.contains("#") || (!ids.isEmpty && !k.contains(.point)) { return .success(.selection(ids)) }
        }

        if k.contains(.point) {
            if let p = parsePoint(token, last: lastPoint ?? request.base) { return .success(.point(p)) }
            if let d = parseNumber(token) {
                if k.contains(.distance) || k.contains(.angle) || k.contains(.integer) { return .success(.number(d)) }
                // Direct distance entry along the cursor direction.
                if let b = request.base ?? lastPoint {
                    var dir = ((cursor ?? b + Vec2(1, 0)) - b)
                    if ortho { dir = abs(dir.x) >= abs(dir.y) ? Vec2(dir.x >= 0 ? 1 : -1, 0) : Vec2(0, dir.y >= 0 ? 1 : -1) }
                    let n = dir.normalized == .zero ? Vec2(1, 0) : dir.normalized
                    return .success(.point(b + n * d))
                }
            }
        }
        if k.contains(.distance) || k.contains(.integer) {
            if let d = parseNumber(token) { return .success(.number(d)) }
        }
        if k.contains(.angle) {
            if let a = parseAngleDegrees(token) { return .success(.number(a)) }
        }
        if k.contains(.string) { return .success(.text(raw)) }
        if k.contains(.keyword) && request.keywords.isEmpty { return .success(.text(token)) }
        return .failure(ParseFailure(message: "Invalid input \"\(token)\". \(expectation(k))"))
    }

    public struct ParseFailure: Error, CustomStringConvertible { public var message: String; public var description: String { message } }

    static func expectation(_ k: Set<InputRequest.Kind>) -> String {
        if k.contains(.point) { return "Enter a point as x,y  @dx,dy  or  @distance<angle." }
        if k.contains(.distance) { return "Enter a distance." }
        if k.contains(.angle) { return "Enter an angle in degrees." }
        if k.contains(.integer) { return "Enter a whole number." }
        return "Try again."
    }

    public static func matchKeyword(_ t: String, _ keywords: [String]) -> String? {
        let l = t.lowercased()
        if let exact = keywords.first(where: { $0.lowercased() == l }) { return exact }
        // Capital letters of the keyword form its shortcut (e.g. "Close" → "C", "cEnter" → "E").
        if let sc = keywords.first(where: { shortcut($0).lowercased() == l }) { return sc }
        let pre = keywords.filter { $0.lowercased().hasPrefix(l) }
        return pre.count == 1 ? pre[0] : nil
    }
    static func shortcut(_ k: String) -> String {
        let caps = k.filter { $0.isUppercase }
        return caps.isEmpty ? String(k.prefix(1)) : String(caps)
    }

    /// Numbers, simple arithmetic and feet-inch forms: 1200, 1.2e3, 3'6", 2400/2, 1000+250.
    public static func parseNumber(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: " ", with: "")
        if let d = Double(t) { return d }
        if t.contains("'") || t.contains("\"") {
            var feet = 0.0, inches = 0.0
            let parts = t.split(separator: "'", omittingEmptySubsequences: false)
            if parts.count == 2 {
                feet = Double(parts[0]) ?? 0
                inches = Double(parts[1].replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "-", with: "")) ?? 0
            } else { inches = Double(t.replacingOccurrences(of: "\"", with: "")) ?? 0 }
            return (feet * 12 + inches) * 25.4
        }
        return evalArithmetic(t)
    }

    static func evalArithmetic(_ t: String) -> Double? {
        guard t.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/()")) != nil,
              t.allSatisfy({ "0123456789.+-*/()eE".contains($0) }) else { return nil }
        var p = ExprParser(Array(t))
        guard let v = p.expr(), p.i == p.c.count else { return nil }
        return v
    }

    struct ExprParser {
        var c: [Character]; var i = 0
        init(_ c: [Character]) { self.c = c }
        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "-" { let op = c[i]; i += 1; guard let r = term() else { return nil }; v = op == "+" ? v + r : v - r }
            return v
        }
        mutating func term() -> Double? {
            guard var v = factor() else { return nil }
            while i < c.count, c[i] == "*" || c[i] == "/" { let op = c[i]; i += 1; guard let r = factor() else { return nil }; v = op == "*" ? v * r : v / r }
            return v
        }
        mutating func factor() -> Double? {
            if i < c.count, c[i] == "(" { i += 1; let v = expr(); if i < c.count, c[i] == ")" { i += 1 }; return v }
            if i < c.count, c[i] == "-" { i += 1; return factor().map { -$0 } }
            var s = ""
            while i < c.count, "0123456789.eE".contains(c[i]) { s.append(c[i]); i += 1 }
            return Double(s)
        }
    }

    static func parseAngleDegrees(_ s: String) -> Double? {
        var t = s.lowercased()
        if t.hasSuffix("d") || t.hasSuffix("°") { t.removeLast() }
        if t.hasSuffix("r") { t.removeLast(); return Double(t).map { deg($0) } }
        return parseNumber(t)
    }

    /// Parses absolute, relative (@) and polar (<) coordinates. A third component (z) is ignored in 2D.
    public static func parsePoint(_ s: String, last: Vec2?) -> Vec2? {
        var t = s
        var relative = false
        if t.hasPrefix("@") { relative = true; t.removeFirst(); if t.isEmpty { return last } }
        if t.hasPrefix("#") { t.removeFirst() } // explicit absolute
        let base = relative ? (last ?? .zero) : .zero
        if let lt = t.firstIndex(of: "<") {
            guard let d = parseNumber(String(t[..<lt])), let a = parseAngleDegrees(String(t[t.index(after: lt)...])) else { return nil }
            return base + Vec2.polar(d, rad(a))
        }
        let parts = t.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3, let x = parseNumber(parts[0]), let y = parseNumber(parts[1]) else { return nil }
        return base + Vec2(x, y)
    }
}
