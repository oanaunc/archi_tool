// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Parses command-line tokens: coordinates (x,y  @dx,dy  @d<angle  d<angle), numbers, keywords, selections (#12,#13).
public enum InputParser {
    public enum ParseError: Error { case message(String) }

    /// Units and UCS applied while parsing (set by the Editor from its document before each parse).
    public static var context = ParseContext()

    /// Point-entry modifiers accepted wherever a point is requested (object snap overrides are handled by the UI).
    /// INTOF: intersection of two picked objects (PRC-017); RH / RV: the next point restricted horizontally / vertically
    /// from the last point (PRC-021).
    public static let pointModifiers = ["FROM", "FRO", "M2P", "MTP", "TT", ".X", ".Y", ".XY", ".XZ", ".YZ", ".Z", "INTOF", "RH", "RV"]
    public static func pointModifier(_ token: String) -> String? {
        let t = token.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "_'"))
        guard pointModifiers.contains(t) else { return nil }
        switch t { case "FRO": return "FROM"; case "MTP": return "M2P"; default: return t }
    }

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
        var t = s.replacingOccurrences(of: " ", with: "")
        if let d = Double(t) { return d }
        if t.rangeOfCharacter(from: .letters) != nil, let u = convertUnitSuffixes(t) {
            if let d = Double(u) { return d }
            t = u
        }
        if t.contains("'") || t.contains("\"") {
            var feet = 0.0, inches = 0.0
            let parts = t.split(separator: "'", omittingEmptySubsequences: false)
            if parts.count == 2 {
                feet = Double(parts[0]) ?? 0
                inches = Double(parts[1].replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "-", with: "")) ?? 0
            } else { inches = Double(t.replacingOccurrences(of: "\"", with: "")) ?? 0 }
            return (feet * 12 + inches) * 25.4 / context.units.mm
        }
        return evalArithmetic(t)
    }

    /// Unit factors in millimetres for suffixed values ("2.5m", "30cm", "12in", "3ft").
    static let unitSuffixes: [(String, Double)] = [("mm", 1), ("cm", 10), ("dm", 100), ("km", 1_000_000), ("m", 1000), ("in", 25.4), ("ft", 304.8), ("yd", 914.4)]

    /// Replaces every number followed by a unit suffix with its value in drawing units. nil if a letter sequence is not a unit.
    public static func convertUnitSuffixes(_ t: String) -> String? {
        let c = Array(t)
        var out = "", i = 0
        while i < c.count {
            if c[i].isNumber || (c[i] == "." && i + 1 < c.count && c[i + 1].isNumber) {
                var num = ""
                while i < c.count, c[i].isNumber || c[i] == "." { num.append(c[i]); i += 1 }
                // exponent (1e3) — only when followed by a digit or sign+digit
                if i + 1 < c.count, c[i] == "e" || c[i] == "E", c[i + 1].isNumber || ((c[i + 1] == "-" || c[i + 1] == "+") && i + 2 < c.count && c[i + 2].isNumber) {
                    num.append(c[i]); i += 1
                    if c[i] == "-" || c[i] == "+" { num.append(c[i]); i += 1 }
                    while i < c.count, c[i].isNumber { num.append(c[i]); i += 1 }
                }
                var word = ""
                var j = i
                while j < c.count, c[j].isLetter { word.append(c[j]); j += 1 }
                if !word.isEmpty {
                    guard let f = unitSuffixes.first(where: { $0.0 == word.lowercased() })?.1, let v = Double(num) else { return nil }
                    out += "(" + fmt(v * f / context.units.mm, 12) + ")"
                    i = j
                } else { out += num }
                continue
            }
            if c[i].isLetter { return nil }
            out.append(c[i]); i += 1
        }
        return out
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

    /// Angles: 45, 45d, 45°, 0.5r (radians), 50g (grads), 45d30'15" (degrees-minutes-seconds), N45d30'E (surveyor bearing).
    public static func parseAngleDegrees(_ s: String) -> Double? {
        var t = s.lowercased().replacingOccurrences(of: " ", with: "")
        if t.isEmpty { return nil }
        // Surveyor's units: N45d30'E, S20W, N, E...
        if let f = t.first, "ns".contains(f), let l = t.last, "ew".contains(l) {
            let inner = String(t.dropFirst().dropLast())
            guard let a = inner.isEmpty ? 0 : parseAngleDegrees(inner) else { return nil }
            switch (f, l) {
            case ("n", "e"): return 90 - a
            case ("n", "w"): return 90 + a
            case ("s", "e"): return 270 + a
            default: return 270 - a
            }
        }
        switch t { case "n": return 90; case "s": return 270; case "e": return 0; case "w": return 180; default: break }
        if t.hasSuffix("r") { t.removeLast(); return parseNumber(t).map { deg($0) } }
        if t.hasSuffix("g") { t.removeLast(); return parseNumber(t).map { $0 * 0.9 } }
        // Degrees-minutes-seconds
        if let di = t.firstIndex(where: { $0 == "d" || $0 == "°" }), t.index(after: di) < t.endIndex {
            guard let d = Double(t[..<di]) else { return nil }
            var rest = String(t[t.index(after: di)...])
            var m = 0.0, sec = 0.0
            if let mi = rest.firstIndex(of: "'") { m = Double(rest[..<mi]) ?? 0; rest = String(rest[rest.index(after: mi)...]) }
            if rest.hasSuffix("\"") { rest.removeLast(); sec = Double(rest) ?? 0 } else if !rest.isEmpty { return nil }
            let sign: Double = d < 0 || t.hasPrefix("-") ? -1 : 1
            return sign * (abs(d) + m / 60 + sec / 3600)
        }
        if t.hasSuffix("d") || t.hasSuffix("°") { t.removeLast() }
        return parseNumber(t)
    }

    /// Parses absolute, relative (@) and polar (<) coordinates. A third component (z) is ignored in 2D.
    /// Coordinates typed without "*" are in the current UCS (InputParser.context.ucs); "*x,y" and "@*dx,dy" are world coordinates.
    public static func parsePoint(_ s: String, last: Vec2?) -> Vec2? {
        var t = s
        var relative = false
        if t.hasPrefix("@") { relative = true; t.removeFirst(); if t.isEmpty { return last } }
        var ucs = context.ucs
        if t.hasPrefix("*") { t.removeFirst(); ucs = .world }
        if t.hasPrefix("#") { t.removeFirst() } // explicit absolute
        guard !t.isEmpty else { return nil }
        let local: Vec2
        if let lt = t.firstIndex(of: "<") {
            guard let d = parseNumber(String(t[..<lt])), let a = parseAngleDegrees(String(t[t.index(after: lt)...])) else { return nil }
            local = Vec2.polar(d, rad(a))
        } else {
            let parts = t.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 || parts.count == 3, let x = parseNumber(parts[0]), let y = parseNumber(parts[1]) else { return nil }
            local = Vec2(x, y)
        }
        if relative { return (last ?? .zero) + ucs.vectorToWorld(local) }
        return ucs.toWorld(local)
    }
}
