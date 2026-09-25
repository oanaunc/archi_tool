// Oanarina Archi Tool — GPL-3.0-or-later
// ISO 10303-21 (STEP physical file) parser used by the IFC importer.
import Foundation

/// A parameter value in a STEP entity instance.
public indirect enum StepValue: Hashable {
    case ref(Int)
    case int(Int)
    case real(Double)
    case string(String)
    case enumeration(String)
    case list([StepValue])
    /// Typed parameter such as IFCLABEL('x') or IFCLENGTHMEASURE(2.5).
    case typed(String, [StepValue])
    case null
    case derived

    public var ref: Int? { if case .ref(let r) = self { return r }; return nil }
    public var list: [StepValue]? { if case .list(let l) = self { return l }; return nil }
    public var refs: [Int] { list?.compactMap { $0.ref } ?? [] }
    public var string: String? {
        switch self {
        case .string(let s): return s
        case .typed(_, let a): return a.first?.string
        default: return nil
        }
    }
    public var double: Double? {
        switch self {
        case .real(let d): return d
        case .int(let i): return Double(i)
        case .typed(_, let a): return a.first?.double
        default: return nil
        }
    }
    public var enumValue: String? { if case .enumeration(let e) = self { return e }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }
    /// Display text of a simple value (used for property values).
    public var text: String? {
        switch self {
        case .string(let s): return s
        case .real(let d): return fmt(d, 6)
        case .int(let i): return "\(i)"
        case .enumeration(let e):
            switch e { case "T": return "true"; case "F": return "false"; case "U": return "unknown"; default: return e }
        case .typed(_, let a): return a.first?.text
        default: return nil
        }
    }
}

public struct StepEntity: Hashable {
    public var id: Int
    /// Upper-case entity type (for complex instances, the first partial type).
    public var type: String
    public var args: [StepValue]
    /// Partial entities of a complex instance `(A(..)B(..))`, keyed by type.
    public var parts: [String: [StepValue]]
    public subscript(_ i: Int) -> StepValue { i < args.count ? args[i] : .null }
}

public enum STEPError: Error, LocalizedError, Equatable {
    case notSTEP
    case syntax(String)
    public var errorDescription: String? {
        switch self {
        case .notSTEP: return "The file is not an ISO 10303-21 (STEP/IFC) file."
        case .syntax(let s): return "STEP syntax error: \(s)"
        }
    }
}

public struct STEPFile {
    public var schema: String
    public var entities: [Int: StepEntity]
    public subscript(_ id: Int?) -> StepEntity? { id.flatMap { entities[$0] } }
    public func all(_ type: String) -> [StepEntity] { entities.values.filter { $0.type == type }.sorted { $0.id < $1.id } }
}

public enum STEPParser {
    public static func parse(_ text: String) throws -> STEPFile {
        try parse(Array(text.utf8))
    }

    public static func parse(_ bytes: [UInt8]) throws -> STEPFile {
        var s = Scanner(b: bytes, i: 0)
        guard s.find("ISO-10303-21") else { throw STEPError.notSTEP }
        var schema = ""
        let headerStart = s.i
        if s.find("FILE_SCHEMA") {
            s.skipWS()
            if let v = try? s.value() { schema = v.list?.first?.list?.first?.string ?? v.list?.first?.string ?? "" }
        }
        s.i = headerStart
        guard s.find("DATA;") else { throw STEPError.syntax("no DATA section") }
        var ents: [Int: StepEntity] = [:]
        while true {
            s.skipWS()
            guard s.i < s.b.count else { break }
            if s.peekWord("ENDSEC") { break }
            guard s.b[s.i] == UInt8(ascii: "#") else {
                // Resynchronise at the next ';'.
                while s.i < s.b.count && s.b[s.i] != UInt8(ascii: ";") { s.i += 1 }
                s.i += 1; continue
            }
            s.i += 1
            let id = s.integer()
            s.skipWS()
            guard s.eat(UInt8(ascii: "=")) else { throw STEPError.syntax("expected '=' after #\(id)") }
            s.skipWS()
            if s.i < s.b.count && s.b[s.i] == UInt8(ascii: "(") {
                // Complex instance: (TYPEA(...) TYPEB(...))
                s.i += 1
                var parts: [String: [StepValue]] = [:]
                var first = ""
                while true {
                    s.skipWS()
                    if s.eat(UInt8(ascii: ")")) { break }
                    guard s.i < s.b.count else { throw STEPError.syntax("unterminated complex instance #\(id)") }
                    let name = s.identifier()
                    guard !name.isEmpty else { throw STEPError.syntax("bad complex instance #\(id)") }
                    s.skipWS()
                    let args = try s.argList()
                    if first.isEmpty { first = name }
                    parts[name] = args
                }
                ents[id] = StepEntity(id: id, type: first, args: parts[first] ?? [], parts: parts)
            } else {
                let name = s.identifier()
                s.skipWS()
                let args = try s.argList()
                ents[id] = StepEntity(id: id, type: name, args: args, parts: [:])
            }
            s.skipWS()
            _ = s.eat(UInt8(ascii: ";"))
        }
        return STEPFile(schema: schema, entities: ents)
    }

    struct Scanner {
        let b: [UInt8]
        var i: Int

        mutating func find(_ word: String) -> Bool {
            let w = Array(word.utf8)
            guard !w.isEmpty, b.count >= w.count else { return false }
            var j = i
            while j + w.count <= b.count {
                if b[j] == w[0] {
                    var ok = true
                    for k in 1..<w.count where b[j + k] != w[k] { ok = false; break }
                    if ok { i = j + w.count; return true }
                }
                j += 1
            }
            return false
        }
        func peekWord(_ word: String) -> Bool {
            let w = Array(word.utf8)
            guard i + w.count <= b.count else { return false }
            for k in 0..<w.count where b[i + k] != w[k] { return false }
            return true
        }
        mutating func eat(_ c: UInt8) -> Bool {
            if i < b.count && b[i] == c { i += 1; return true }
            return false
        }
        mutating func skipWS() {
            while i < b.count {
                let c = b[i]
                if c == 32 || c == 9 || c == 10 || c == 13 { i += 1; continue }
                if c == UInt8(ascii: "/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "*") {
                    i += 2
                    while i + 1 < b.count && !(b[i] == UInt8(ascii: "*") && b[i + 1] == UInt8(ascii: "/")) { i += 1 }
                    i = min(b.count, i + 2); continue
                }
                break
            }
        }
        mutating func integer() -> Int {
            var v = 0
            while i < b.count, b[i] >= 48, b[i] <= 57 { v = v * 10 + Int(b[i] - 48); i += 1 }
            return v
        }
        mutating func identifier() -> String {
            let st = i
            while i < b.count {
                let c = b[i]
                if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 { i += 1 } else { break }
            }
            return String(decoding: b[st..<i], as: UTF8.self).uppercased()
        }
        mutating func argList() throws -> [StepValue] {
            guard eat(UInt8(ascii: "(")) else { throw STEPError.syntax("expected '(' at byte \(i)") }
            var out: [StepValue] = []
            skipWS()
            if eat(UInt8(ascii: ")")) { return out }
            while true {
                skipWS()
                out.append(try value())
                skipWS()
                if eat(UInt8(ascii: ",")) { continue }
                if eat(UInt8(ascii: ")")) { return out }
                throw STEPError.syntax("expected ',' or ')' at byte \(i)")
            }
        }
        mutating func value() throws -> StepValue {
            skipWS()
            guard i < b.count else { throw STEPError.syntax("unexpected end of file") }
            let c = b[i]
            switch c {
            case UInt8(ascii: "#"): i += 1; return .ref(integer())
            case UInt8(ascii: "$"): i += 1; return .null
            case UInt8(ascii: "*"): i += 1; return .derived
            case UInt8(ascii: "'"): return .string(try string())
            case UInt8(ascii: "\""):
                // binary literal — keep as string
                i += 1; let st = i
                while i < b.count && b[i] != UInt8(ascii: "\"") { i += 1 }
                let s = String(decoding: b[st..<i], as: UTF8.self); i += 1
                return .string(s)
            case UInt8(ascii: "."):
                i += 1; let st = i
                while i < b.count && b[i] != UInt8(ascii: ".") { i += 1 }
                let e = String(decoding: b[st..<i], as: UTF8.self).uppercased(); i += 1
                return .enumeration(e)
            case UInt8(ascii: "("): return .list(try argList())
            default:
                if (c >= 48 && c <= 57) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") {
                    let st = i; var isReal = false
                    i += 1
                    while i < b.count {
                        let d = b[i]
                        if d >= 48 && d <= 57 { i += 1 }
                        else if d == UInt8(ascii: ".") || d == UInt8(ascii: "E") || d == UInt8(ascii: "e") { isReal = true; i += 1 }
                        else if (d == UInt8(ascii: "-") || d == UInt8(ascii: "+")) && (b[i - 1] == UInt8(ascii: "E") || b[i - 1] == UInt8(ascii: "e")) { i += 1 }
                        else { break }
                    }
                    let t = String(decoding: b[st..<i], as: UTF8.self)
                    if !isReal, let v = Int(t) { return .int(v) }
                    var tt = t
                    if tt.hasSuffix(".") { tt += "0" }
                    tt = tt.replacingOccurrences(of: ".E", with: ".0E").replacingOccurrences(of: ".e", with: ".0e")
                    return .real(Double(tt) ?? 0)
                }
                let name = identifier()
                guard !name.isEmpty else { throw STEPError.syntax("unexpected character at byte \(i)") }
                skipWS()
                if i < b.count && b[i] == UInt8(ascii: "(") { return .typed(name, try argList()) }
                return .enumeration(name)
            }
        }
        mutating func string() throws -> String {
            i += 1
            var raw: [UInt8] = []
            while i < b.count {
                if b[i] == UInt8(ascii: "'") {
                    if i + 1 < b.count && b[i + 1] == UInt8(ascii: "'") { raw.append(UInt8(ascii: "'")); i += 2; continue }
                    i += 1
                    return STEPParser.decode(raw)
                }
                raw.append(b[i]); i += 1
            }
            throw STEPError.syntax("unterminated string")
        }
    }

    /// Decodes ISO 10303-21 string escapes (\X2\…\X0\, \X4\…\X0\, \X\hh, \S\c, \\).
    static func decode(_ raw: [UInt8]) -> String {
        guard raw.contains(UInt8(ascii: "\\")) else { return String(decoding: raw, as: UTF8.self) }
        var out = ""
        var i = 0
        var plain: [UInt8] = []
        func flush() { if !plain.isEmpty { out += String(decoding: plain, as: UTF8.self); plain.removeAll() } }
        func hex(_ from: Int, _ n: Int) -> UInt32? {
            guard from + n <= raw.count else { return nil }
            return UInt32(String(decoding: raw[from..<(from + n)], as: UTF8.self), radix: 16)
        }
        func starts(_ s: String, at k: Int) -> Bool {
            let w = Array(s.utf8)
            guard k + w.count <= raw.count else { return false }
            for j in 0..<w.count where raw[k + j] != w[j] { return false }
            return true
        }
        while i < raw.count {
            if raw[i] == UInt8(ascii: "\\") {
                if starts("\\X2\\", at: i) || starts("\\X4\\", at: i) {
                    let width = raw[i + 2] == UInt8(ascii: "2") ? 4 : 8
                    flush(); i += 4
                    while i < raw.count && !starts("\\X0\\", at: i) {
                        if let v = hex(i, width), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
                        i += width
                    }
                    i += 4; continue
                }
                if starts("\\X\\", at: i), let v = hex(i + 3, 2), let u = Unicode.Scalar(v) { flush(); out.unicodeScalars.append(u); i += 5; continue }
                if starts("\\S\\", at: i), i + 3 < raw.count, let u = Unicode.Scalar(UInt32(raw[i + 3]) + 128) { flush(); out.unicodeScalars.append(u); i += 4; continue }
                if starts("\\P", at: i), i + 3 < raw.count, raw[i + 3] == UInt8(ascii: "\\") { i += 4; continue }
                if starts("\\\\", at: i) { plain.append(UInt8(ascii: "\\")); i += 2; continue }
            }
            plain.append(raw[i]); i += 1
        }
        flush()
        return out
    }
}
