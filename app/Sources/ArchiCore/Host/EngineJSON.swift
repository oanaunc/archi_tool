// Oanarina Archi Tool — GPL-3.0-or-later
// A small JSON value with its own parser and writer for the engine protocol (archi-engine): deterministic key order,
// compact numbers, no dependence on JSONSerialization's platform-specific number/bool bridging.
import Foundation

/// One key/value pair of a JSON object (objects keep their insertion order).
public struct EngineJSONField: Equatable {
    public var key: String
    public var value: EngineJSON
    public init(_ key: String, _ value: EngineJSON) { self.key = key; self.value = value }
}

public indirect enum EngineJSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EngineJSON])
    case object([EngineJSONField])

    // MARK: Constructors (explicit, so large payloads type-check quickly on every platform)
    public static func int(_ v: Int) -> EngineJSON { .number(Double(v)) }
    public static func point(_ p: Vec2) -> EngineJSON { .array([.number(p.x), .number(p.y)]) }
    public static func point3(_ p: Vec3) -> EngineJSON { .array([.number(p.x), .number(p.y), .number(p.z)]) }
    public static func strings(_ a: [String]) -> EngineJSON { .array(a.map { EngineJSON.string($0) }) }
    public static func ints(_ a: [Int]) -> EngineJSON { .array(a.map { EngineJSON.int($0) }) }
    public static func numbers(_ a: [Double]) -> EngineJSON { .array(a.map { EngineJSON.number($0) }) }
    public static func optString(_ s: String?) -> EngineJSON { s.map { EngineJSON.string($0) } ?? .null }

    // MARK: Accessors
    public subscript(key: String) -> EngineJSON? {
        guard case .object(let f) = self else { return nil }
        return f.first(where: { $0.key == key })?.value
    }
    public subscript(index: Int) -> EngineJSON? {
        guard case .array(let a) = self, a.indices.contains(index) else { return nil }
        return a[index]
    }
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let d): return EngineJSON.format(d)
        case .bool(let b): return b ? "1" : "0"
        default: return nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    public var intValue: Int? {
        guard let d = doubleValue, d.isFinite, abs(d) < 9e15 else { return nil }
        return Int(d.rounded())
    }
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .string(let s): return SystemVariables.parseFlag(s)
        default: return nil
        }
    }
    public var arrayValue: [EngineJSON]? { if case .array(let a) = self { return a }; return nil }
    public var fields: [EngineJSONField]? { if case .object(let f) = self { return f }; return nil }
    public var isNull: Bool { self == .null }
    /// [x, y] or {x, y}.
    public var vec2: Vec2? {
        if let a = arrayValue, a.count >= 2, let x = a[0].doubleValue, let y = a[1].doubleValue { return Vec2(x, y) }
        if let x = self["x"]?.doubleValue, let y = self["y"]?.doubleValue { return Vec2(x, y) }
        return nil
    }

    // MARK: Writing
    /// Compact single-line JSON.
    public var serialized: String {
        var out = ""
        out.reserveCapacity(256)
        EngineJSON.write(self, into: &out)
        return out
    }

    static func write(_ v: EngineJSON, into out: inout String) {
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let d): out += format(d)
        case .string(let s): writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, e) in a.enumerated() {
                if i > 0 { out += "," }
                write(e, into: &out)
            }
            out += "]"
        case .object(let f):
            out += "{"
            for (i, e) in f.enumerated() {
                if i > 0 { out += "," }
                writeString(e.key, into: &out)
                out += ":"
                write(e.value, into: &out)
            }
            out += "}"
        }
    }

    /// Numbers are rounded to 6 decimals (well below a micrometre in millimetre drawings); integers print without ".0".
    public static func format(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        let r = (d * 1_000_000).rounded() / 1_000_000
        if r == r.rounded(), abs(r) < 1e15 {
            let i = Int(r)
            return String(i)
        }
        return "\(r)"
    }

    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    // MARK: Parsing
    public struct ParseError: Error, Equatable { public var message: String }

    public static func parse(_ text: String) throws -> EngineJSON {
        var p = Parser(Array(text.utf8))
        p.skipSpace()
        let v = try p.value(depth: 0)
        p.skipSpace()
        if p.i < p.b.count { throw ParseError(message: "unexpected data after the JSON value") }
        return v
    }

    struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func skipSpace() {
            while i < b.count, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D { i += 1 }
        }

        mutating func value(depth: Int) throws -> EngineJSON {
            guard depth < 512 else { throw ParseError(message: "nesting too deep") }
            guard i < b.count else { throw ParseError(message: "unexpected end of input") }
            let c = b[i]
            switch c {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func literal(_ s: String) throws {
            let u = Array(s.utf8)
            guard i + u.count <= b.count, Array(b[i..<(i + u.count)]) == u else { throw ParseError(message: "invalid literal at \(i)") }
            i += u.count
        }

        mutating func number() throws -> Double {
            let start = i
            while i < b.count {
                let c = b[i]
                let isNum = (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E")
                if !isNum { break }
                i += 1
            }
            guard i > start, let s = String(bytes: b[start..<i], encoding: .utf8), let d = Double(s) else {
                throw ParseError(message: "invalid value at \(start)")
            }
            return d
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= b.count, let s = String(bytes: b[i..<(i + 4)], encoding: .utf8), let v = UInt32(s, radix: 16) else {
                throw ParseError(message: "invalid \\u escape at \(i)")
            }
            i += 4
            return v
        }

        mutating func string() throws -> String {
            i += 1 // opening quote
            var bytes: [UInt8] = []
            while true {
                guard i < b.count else { throw ParseError(message: "unterminated string") }
                let c = b[i]
                i += 1
                if c == UInt8(ascii: "\"") { break }
                if c != UInt8(ascii: "\\") { bytes.append(c); continue }
                guard i < b.count else { throw ParseError(message: "unterminated escape") }
                let e = b[i]
                i += 1
                switch e {
                case UInt8(ascii: "n"): bytes.append(0x0A)
                case UInt8(ascii: "r"): bytes.append(0x0D)
                case UInt8(ascii: "t"): bytes.append(0x09)
                case UInt8(ascii: "b"): bytes.append(0x08)
                case UInt8(ascii: "f"): bytes.append(0x0C)
                case UInt8(ascii: "u"):
                    var v = try hex4()
                    if v >= 0xD800 && v < 0xDC00, i + 6 <= b.count, b[i] == UInt8(ascii: "\\"), b[i + 1] == UInt8(ascii: "u") {
                        i += 2
                        let lo = try hex4()
                        v = 0x10000 + ((v - 0xD800) << 10) + (lo &- 0xDC00)
                    }
                    let scalar = Unicode.Scalar(v) ?? "?"
                    bytes.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: bytes.append(e)
                }
            }
            return String(decoding: bytes, as: UTF8.self)
        }

        mutating func array(depth: Int) throws -> EngineJSON {
            i += 1
            var out: [EngineJSON] = []
            skipSpace()
            if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return .array(out) }
            while true {
                skipSpace()
                out.append(try value(depth: depth + 1))
                skipSpace()
                guard i < b.count else { throw ParseError(message: "unterminated array") }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "]") { i += 1; return .array(out) }
                throw ParseError(message: "expected , or ] at \(i)")
            }
        }

        mutating func object(depth: Int) throws -> EngineJSON {
            i += 1
            var out: [EngineJSONField] = []
            skipSpace()
            if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .object(out) }
            while true {
                skipSpace()
                guard i < b.count, b[i] == UInt8(ascii: "\"") else { throw ParseError(message: "expected a key at \(i)") }
                let k = try string()
                skipSpace()
                guard i < b.count, b[i] == UInt8(ascii: ":") else { throw ParseError(message: "expected : at \(i)") }
                i += 1
                skipSpace()
                let v = try value(depth: depth + 1)
                out.append(EngineJSONField(k, v))
                skipSpace()
                guard i < b.count else { throw ParseError(message: "unterminated object") }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "}") { i += 1; return .object(out) }
                throw ParseError(message: "expected , or } at \(i)")
            }
        }
    }
}

/// Builds a JSON object field by field (keeps the order the fields are set in).
public struct EngineObject {
    public private(set) var fields: [EngineJSONField] = []
    public init() {}
    public mutating func set(_ key: String, _ value: EngineJSON) {
        if let k = fields.firstIndex(where: { $0.key == key }) { fields[k].value = value } else { fields.append(EngineJSONField(key, value)) }
    }
    public mutating func set(_ key: String, _ s: String) { set(key, EngineJSON.string(s)) }
    public mutating func set(_ key: String, _ d: Double) { set(key, EngineJSON.number(d)) }
    public mutating func set(_ key: String, _ i: Int) { set(key, EngineJSON.number(Double(i))) }
    public mutating func set(_ key: String, _ b: Bool) { set(key, EngineJSON.bool(b)) }
    public var json: EngineJSON { .object(fields) }
}
