// Oanarina Archi Tool — GPL-3.0-or-later
// AutoLISP compatibility subset (SCR-005): a small Lisp interpreter for common .lsp routines — defun (including
// c:COMMAND functions that become commands), setq, lambda, if/cond/while/repeat/foreach/progn/and/or, arithmetic,
// trigonometry, list functions (car/cdr/cons/list/append/nth/assoc/member/reverse/length/mapcar/apply), strings
// (strcat/substr/strlen/strcase/itoa/atoi/rtos/atof/vl-string-search), geometry (polar/distance/angle/inters),
// system variables (getvar/setvar), (command …) and entity access (entlast/entget/entdel/entmod for 0/8/10/11/40/62,
// ssget "X" with a (0 . "TYPE") / (8 . "LAYER") filter, sslength/ssname). Interactive input functions (getpoint …)
// return nil. Routines run after the invoking command finishes, so each (command …) is its own undo step, like AutoCAD.
import Foundation

public indirect enum LispValue: Equatable, CustomStringConvertible {
    case nil_, t
    case int(Int), real(Double), str(String), sym(String)
    case list([LispValue])
    case pair(LispValue, LispValue)
    case lambda(params: [String], locals: [String], body: [LispValue])
    case builtin(String)
    case ename(EntityID)
    case pickset([EntityID])

    public var description: String {
        switch self {
        case .nil_: return "nil"
        case .t: return "T"
        case .int(let i): return "\(i)"
        case .real(let d): return fmt(d, 6).contains(".") || fmt(d, 6).contains("e") ? fmt(d, 6) : fmt(d, 6) + ".0"
        case .str(let s): return "\"" + s + "\""
        case .sym(let s): return s.uppercased()
        case .list(let l): return "(" + l.map(\.description).joined(separator: " ") + ")"
        case .pair(let a, let b): return "(\(a) . \(b))"
        case .lambda: return "#<USUBR>"
        case .builtin(let n): return "#<SUBR @\(n)>"
        case .ename(let id): return "<Entity name: \(String(id, radix: 16))>"
        case .pickset(let s): return "<Selection set: \(s.count)>"
        }
    }
    var isNil: Bool { if case .nil_ = self { return true }; if case .list(let l) = self { return l.isEmpty }; return false }
    var number: Double? { switch self { case .int(let i): return Double(i); case .real(let d): return d; default: return nil } }
    var items: [LispValue] { if case .list(let l) = self { return l }; return [] }
    var point: Vec2? { let n = items.compactMap(\.number); return n.count >= 2 ? Vec2(n[0], n[1]) : nil }
    static func bool(_ b: Bool) -> LispValue { b ? .t : .nil_ }
    static func pt(_ p: Vec2, _ z: Double = 0) -> LispValue { .list([.real(p.x), .real(p.y), .real(z)]) }
}

public struct LispError: Error, LocalizedError { public let message: String; public var errorDescription: String? { "; error: " + message } }

@MainActor
public final class LispInterpreter {
    public static let shared = LispInterpreter()
    public var globals: [String: LispValue] = [:]
    var scopes: [[String: LispValue]] = []
    public weak var editor: Editor?
    var steps = 0
    public var output: [String] = []

    public init() {}

    // MARK: reader
    public static func read(_ src: String) throws -> [LispValue] {
        var i = src.startIndex
        var out: [LispValue] = []
        func skip() {
            while i < src.endIndex {
                let c = src[i]
                if c == ";" { while i < src.endIndex && src[i] != "\n" { i = src.index(after: i) } }
                else if c.isWhitespace { i = src.index(after: i) } else { break }
            }
        }
        func form() throws -> LispValue {
            skip()
            guard i < src.endIndex else { throw LispError(message: "malformed list on input") }
            let c = src[i]
            if c == "(" {
                i = src.index(after: i)
                var items: [LispValue] = []
                while true {
                    skip()
                    guard i < src.endIndex else { throw LispError(message: "malformed list on input (missing ')')") }
                    if src[i] == ")" { i = src.index(after: i); break }
                    if src[i] == ".", src.index(after: i) < src.endIndex, src[src.index(after: i)].isWhitespace, let first = items.last, items.count == 1 {
                        i = src.index(after: i)
                        let second = try form()
                        skip()
                        guard i < src.endIndex, src[i] == ")" else { throw LispError(message: "bad dotted pair") }
                        i = src.index(after: i)
                        return .pair(first, second)
                    }
                    items.append(try form())
                }
                return .list(items)
            }
            if c == ")" { throw LispError(message: "extra right paren on input") }
            if c == "'" { i = src.index(after: i); return .list([.sym("quote"), try form()]) }
            if c == "\"" {
                i = src.index(after: i)
                var s = ""
                while i < src.endIndex && src[i] != "\"" {
                    if src[i] == "\\", src.index(after: i) < src.endIndex {
                        i = src.index(after: i)
                        switch src[i] { case "n": s.append("\n"); case "t": s.append("\t"); default: s.append(src[i]) }
                    } else { s.append(src[i]) }
                    i = src.index(after: i)
                }
                guard i < src.endIndex else { throw LispError(message: "unterminated string") }
                i = src.index(after: i)
                return .str(s)
            }
            var tok = ""
            while i < src.endIndex, !src[i].isWhitespace, !"()'\";".contains(src[i]) { tok.append(src[i]); i = src.index(after: i) }
            if let n = Int(tok) { return .int(n) }
            if let d = Double(tok) { return .real(d) }
            if tok.lowercased() == "nil" { return .nil_ }
            if tok.lowercased() == "t" { return .t }
            return .sym(tok.lowercased())
        }
        while true { skip(); if i >= src.endIndex { break }; out.append(try form()) }
        return out
    }

    // MARK: evaluation
    func lookup(_ s: String) -> LispValue {
        for sc in scopes.reversed() { if let v = sc[s] { return v } }
        if let v = globals[s] { return v }
        if s == "pi" { return .real(.pi) }
        if LispInterpreter.builtins.contains(s) { return .builtin(s) }
        return .nil_
    }
    func assign(_ s: String, _ v: LispValue) {
        for k in scopes.indices.reversed() where scopes[k][s] != nil { scopes[k][s] = v; return }
        globals[s] = v
    }

    public func run(_ src: String) async throws -> LispValue {
        var last = LispValue.nil_
        for f in try LispInterpreter.read(src) { last = try await eval(f) }
        return last
    }

    public func eval(_ x: LispValue) async throws -> LispValue {
        steps += 1
        if steps > 5_000_000 { throw LispError(message: "too many evaluation steps (infinite loop?)") }
        switch x {
        case .sym(let s): return lookup(s)
        case .list(let l):
            guard let head = l.first else { return .nil_ }
            if case .sym(let op) = head, let v = try await special(op, Array(l.dropFirst())) { return v }
            let fn = try await eval(head)
            var args: [LispValue] = []
            for a in l.dropFirst() { args.append(try await eval(a)) }
            return try await apply(fn, args, name: head.description)
        default: return x
        }
    }

    func apply(_ fn: LispValue, _ args: [LispValue], name: String = "") async throws -> LispValue {
        switch fn {
        case .sym(let s):
            // 'fname or '+ passed as a function.
            let f = lookup(s)
            if case .sym = f { throw LispError(message: "no function definition: \(s.uppercased())") }
            return try await apply(f, args, name: s)
        case .list(let l) where l.first == .sym("lambda"):
            return try await apply(try await eval(fn), args, name: "lambda")
        case .builtin(let b): return try await builtin(b, args)
        case .lambda(let params, let locals, let body):
            var sc: [String: LispValue] = [:]
            for (i, p) in params.enumerated() { sc[p] = i < args.count ? args[i] : .nil_ }
            for l in locals { sc[l] = .nil_ }
            scopes.append(sc)
            defer { scopes.removeLast() }
            var r = LispValue.nil_
            for f in body { r = try await eval(f) }
            return r
        default: throw LispError(message: "no function definition: \(name)")
        }
    }

    func truthy(_ v: LispValue) -> Bool { !v.isNil }

    /// Special forms; nil when `op` is not one.
    func special(_ op: String, _ a: [LispValue]) async throws -> LispValue? {
        switch op {
        case "quote": return a.first ?? .nil_
        case "function": return try await eval(a.first ?? .nil_)
        case "setq":
            var r = LispValue.nil_
            var i = 0
            while i + 1 < a.count {
                guard case .sym(let s) = a[i] else { throw LispError(message: "bad argument type: symbol \(a[i])") }
                r = try await eval(a[i + 1]); assign(s, r); i += 2
            }
            return r
        case "defun":
            guard a.count >= 2, case .sym(let name) = a[0] else { throw LispError(message: "bad defun") }
            let (params, locals) = LispInterpreter.paramList(a[1])
            globals[name] = .lambda(params: params, locals: locals, body: Array(a.dropFirst(2)))
            if name.hasPrefix("c:"), let ed = editor { registerCommand(String(name.dropFirst(2)).uppercased(), ed: ed) }
            return .sym(name)
        case "lambda":
            let (params, locals) = LispInterpreter.paramList(a.first ?? .nil_)
            return .lambda(params: params, locals: locals, body: Array(a.dropFirst()))
        case "if":
            if truthy(try await eval(a.first ?? .nil_)) { return a.count > 1 ? try await eval(a[1]) : .nil_ }
            return a.count > 2 ? try await eval(a[2]) : .nil_
        case "cond":
            for clause in a {
                let c = clause.items
                guard let test = c.first else { continue }
                let v = try await eval(test)
                if truthy(v) { var r = v; for f in c.dropFirst() { r = try await eval(f) }; return r }
            }
            return .nil_
        case "progn":
            var r = LispValue.nil_; for f in a { r = try await eval(f) }; return r
        case "while":
            var r = LispValue.nil_
            while truthy(try await eval(a.first ?? .nil_)) { for f in a.dropFirst() { r = try await eval(f) } }
            return r
        case "repeat":
            let n = Int(try await eval(a.first ?? .int(0)).number ?? 0)
            var r = LispValue.nil_
            for _ in 0..<max(n, 0) { for f in a.dropFirst() { r = try await eval(f) } }
            return r
        case "foreach":
            guard a.count >= 2, case .sym(let v) = a[0] else { throw LispError(message: "bad foreach") }
            let lst = try await eval(a[1]).items
            var r = LispValue.nil_
            scopes.append([v: .nil_])
            defer { scopes.removeLast() }
            for item in lst { scopes[scopes.count - 1][v] = item; for f in a.dropFirst(2) { r = try await eval(f) } }
            return r
        case "and": for f in a { if !truthy(try await eval(f)) { return .nil_ } }; return .t
        case "or": for f in a { if truthy(try await eval(f)) { return .t } }; return .nil_
        default: return nil
        }
    }

    static func paramList(_ v: LispValue) -> ([String], [String]) {
        var params: [String] = [], locals: [String] = [], afterSlash = false
        for p in v.items { if case .sym(let s) = p { if s == "/" { afterSlash = true } else if afterSlash { locals.append(s) } else { params.append(s) } } }
        return (params, locals)
    }

    static let builtins: Set<String> = ["+", "-", "*", "/", "=", "/=", "<", ">", "<=", ">=", "1+", "1-", "abs", "sqrt", "sin", "cos", "atan", "expt", "fix", "float", "rem",
        "min", "max", "car", "cdr", "cadr", "caddr", "cddr", "caar", "cdar", "cons", "list", "append", "length", "nth", "reverse", "assoc", "member", "last", "null", "not",
        "atom", "listp", "numberp", "eq", "equal", "strcat", "strlen", "substr", "itoa", "atoi", "rtos", "atof", "strcase", "vl-string-search", "princ", "prin1", "print",
        "terpri", "prompt", "getvar", "setvar", "command", "polar", "distance", "angle", "inters", "entlast", "entget", "entdel", "entmod", "ssget", "sslength", "ssname",
        "mapcar", "apply", "type", "getpoint", "getreal", "getint", "getstring", "getdist", "getangle", "getcorner", "getkword", "initget", "alert", "pi", "zerop", "minusp",
        "boundp", "read", "vl-princ-to-string", "gcd", "logand", "logior", "ascii", "chr", "exp", "log", "cadddr", "vl-remove", "vl-sort", "vl-position", "subst"]

    func num(_ v: LispValue, _ f: String) throws -> Double { guard let n = v.number else { throw LispError(message: "bad argument type: numberp: \(v) in \(f)") }; return n }
    func arith(_ args: [LispValue], _ op: (Double, Double) -> Double, _ iop: ((Int, Int) -> Int)?, _ f: String) throws -> LispValue {
        guard var acc = args.first else { return .int(0) }
        for b in args.dropFirst() {
            if case .int(let x) = acc, case .int(let y) = b, let iop { acc = .int(iop(x, y)) } else { acc = .real(op(try num(acc, f), try num(b, f))) }
        }
        return acc
    }
    static func text(_ v: LispValue) -> String { if case .str(let s) = v { return s }; return v.description }

    func builtin(_ f: String, _ a: [LispValue]) async throws -> LispValue {
        func arg(_ i: Int) -> LispValue { i < a.count ? a[i] : .nil_ }
        func s(_ i: Int) -> String { if case .str(let x) = arg(i) { return x }; if case .sym(let x) = arg(i) { return x }; return "" }
        switch f {
        case "+": return try arith(a, +, { $0 &+ $1 }, f)
        case "*": return try arith(a, *, { $0 &* $1 }, f)
        case "-": if a.count == 1 { if case .int(let i) = a[0] { return .int(-i) }; return .real(-(try num(a[0], f))) }; return try arith(a, -, { $0 &- $1 }, f)
        case "/":
            if a.dropFirst().contains(where: { $0.number == 0 }) { throw LispError(message: "divide by zero") }
            return try arith(a, /, { $0 / $1 }, f)
        case "=", "/=", "<", ">", "<=", ">=":
            if f == "=" || f == "/=", let x = a.first, case .str = x { let eq = a.allSatisfy { $0 == x }; return .bool(f == "=" ? eq : !eq) }
            let n = try a.map { try num($0, f) }
            guard n.count >= 2 else { return .t }
            let ok: Bool
            switch f {
            case "=": ok = n.dropFirst().allSatisfy { $0 == n[0] }
            case "/=": ok = n[0] != n[1]
            case "<": ok = zip(n, n.dropFirst()).allSatisfy { $0 < $1 }
            case ">": ok = zip(n, n.dropFirst()).allSatisfy { $0 > $1 }
            case "<=": ok = zip(n, n.dropFirst()).allSatisfy { $0 <= $1 }
            default: ok = zip(n, n.dropFirst()).allSatisfy { $0 >= $1 }
            }
            return .bool(ok)
        case "1+": if case .int(let i) = arg(0) { return .int(i + 1) }; return .real(try num(arg(0), f) + 1)
        case "1-": if case .int(let i) = arg(0) { return .int(i - 1) }; return .real(try num(arg(0), f) - 1)
        case "abs": if case .int(let i) = arg(0) { return .int(abs(i)) }; return .real(abs(try num(arg(0), f)))
        case "sqrt": return .real(sqrt(try num(arg(0), f)))
        case "sin": return .real(sin(try num(arg(0), f)))
        case "cos": return .real(cos(try num(arg(0), f)))
        case "exp": return .real(exp(try num(arg(0), f)))
        case "log": return .real(log(try num(arg(0), f)))
        case "atan": return a.count > 1 ? .real(atan2(try num(a[0], f), try num(a[1], f))) : .real(atan(try num(arg(0), f)))
        case "expt":
            if case .int(let b) = arg(0), case .int(let e) = arg(1), e >= 0 { return .int(Int(pow(Double(b), Double(e)))) }
            return .real(pow(try num(arg(0), f), try num(arg(1), f)))
        case "fix": return .int(Int(try num(arg(0), f)))
        case "float": return .real(try num(arg(0), f))
        case "rem": if case .int(let x) = arg(0), case .int(let y) = arg(1), y != 0 { return .int(x % y) }; return .real(fmod(try num(arg(0), f), try num(arg(1), f)))
        case "gcd": if case .int(var x) = arg(0), case .int(var y) = arg(1) { while y != 0 { (x, y) = (y, x % y) }; return .int(abs(x)) }; return .int(0)
        case "min", "max":
            let n = try a.map { try num($0, f) }
            guard let r = f == "min" ? n.min() : n.max() else { return .int(0) }
            return a.allSatisfy({ if case .int = $0 { return true }; return false }) ? .int(Int(r)) : .real(r)
        case "zerop": return .bool(try num(arg(0), f) == 0)
        case "minusp": return .bool(try num(arg(0), f) < 0)
        case "logand": return .int(a.compactMap { if case .int(let i) = $0 { return i }; return nil }.reduce(-1, &))
        case "logior": return .int(a.compactMap { if case .int(let i) = $0 { return i }; return nil }.reduce(0, |))
        case "car": if case .pair(let x, _) = arg(0) { return x }; return arg(0).items.first ?? .nil_
        case "cdr": if case .pair(_, let y) = arg(0) { return y }; return .list(Array(arg(0).items.dropFirst()))
        case "cadr": return arg(0).items.count > 1 ? arg(0).items[1] : .nil_
        case "caddr": return arg(0).items.count > 2 ? arg(0).items[2] : .nil_
        case "cadddr": return arg(0).items.count > 3 ? arg(0).items[3] : .nil_
        case "cddr": return .list(Array(arg(0).items.dropFirst(2)))
        case "caar": return try await builtin("car", [try await builtin("car", [arg(0)])])
        case "cdar": return try await builtin("cdr", [try await builtin("car", [arg(0)])])
        case "cons":
            if case .list(let l) = arg(1) { return .list([arg(0)] + l) }
            if case .nil_ = arg(1) { return .list([arg(0)]) }
            return .pair(arg(0), arg(1))
        case "list": return .list(a)
        case "append": return .list(a.flatMap(\.items))
        case "length": if case .str(let x) = arg(0) { return .int(x.count) }; return .int(arg(0).items.count)
        case "nth": let i = Int(try num(arg(0), f)); let l = arg(1).items; return i >= 0 && i < l.count ? l[i] : .nil_
        case "reverse": return .list(arg(0).items.reversed())
        case "last": return arg(0).items.last ?? .nil_
        case "assoc":
            for item in arg(1).items {
                switch item {
                case .pair(let k, _) where k == arg(0): return item
                case .list(let l) where l.first == arg(0): return item
                default: continue
                }
            }
            return .nil_
        case "member": let l = arg(1).items; if let i = l.firstIndex(of: arg(0)) { return .list(Array(l[i...])) }; return .nil_
        case "vl-position": return arg(1).items.firstIndex(of: arg(0)).map { .int($0) } ?? .nil_
        case "vl-remove": return .list(arg(1).items.filter { $0 != arg(0) })
        case "subst": return .list(arg(2).items.map { $0 == arg(1) ? arg(0) : $0 })
        case "vl-sort":
            var l = arg(0).items
            var err: Error?
            // Insertion sort with the Lisp predicate (async).
            var i = 1
            while i < l.count {
                var j = i
                while j > 0 {
                    let lt: Bool
                    do { lt = truthy(try await apply(arg(1), [l[j], l[j - 1]])) } catch { err = error; lt = false }
                    if !lt { break }
                    l.swapAt(j, j - 1); j -= 1
                }
                i += 1
            }
            if let err { throw err }
            return .list(l)
        case "null", "not": return .bool(arg(0).isNil)
        case "atom": if case .list(let l) = arg(0) { return .bool(l.isEmpty) }; if case .pair = arg(0) { return .nil_ }; return .t
        case "listp": if case .list = arg(0) { return .t }; if case .pair = arg(0) { return .t }; return .bool(arg(0).isNil)
        case "numberp": return .bool(arg(0).number != nil)
        case "boundp": if case .sym(let x) = arg(0) { return .bool(!lookup(x).isNil) }; return .nil_
        case "eq", "equal":
            if f == "equal", a.count > 2, let x = arg(0).number, let y = arg(1).number, let tol = arg(2).number { return .bool(abs(x - y) <= tol) }
            if let x = arg(0).number, let y = arg(1).number { return .bool(x == y) }
            return .bool(arg(0) == arg(1))
        case "type":
            switch arg(0) {
            case .int: return .sym("int"); case .real: return .sym("real"); case .str: return .sym("str"); case .sym: return .sym("sym")
            case .list, .pair: return .sym("list"); case .lambda: return .sym("usubr"); case .builtin: return .sym("subr")
            case .ename: return .sym("ename"); case .pickset: return .sym("pickset"); default: return .nil_
            }
        case "strcat": return .str(a.map { LispInterpreter.text($0) }.joined())
        case "strlen": return .int(a.reduce(0) { $0 + LispInterpreter.text($1).count })
        case "substr":
            let str = Array(s(0)); let start = max(Int(try num(arg(1), f)) - 1, 0)
            guard start < str.count else { return .str("") }
            let n = a.count > 2 ? Int(try num(arg(2), f)) : str.count - start
            return .str(String(str[start..<min(str.count, start + max(n, 0))]))
        case "strcase": return .str(arg(1).isNil ? s(0).uppercased() : s(0).lowercased())
        case "itoa": return .str("\(Int(try num(arg(0), f)))")
        case "atoi": return .int(Int(Double(s(0).trimmingCharacters(in: .whitespaces)) ?? 0))
        case "atof": return .real(Double(s(0).trimmingCharacters(in: .whitespaces)) ?? 0)
        case "rtos": return .str(fmt(try num(arg(0), f), a.count > 2 ? Int(try num(arg(2), f)) : 4))
        case "vl-string-search": if let r = s(1).range(of: s(0)) { return .int(s(1).distance(from: s(1).startIndex, to: r.lowerBound)) }; return .nil_
        case "vl-princ-to-string": return .str(LispInterpreter.text(arg(0)))
        case "ascii": return .int(Int(s(0).unicodeScalars.first?.value ?? 0))
        case "chr": return .str(String(UnicodeScalar(UInt32(try num(arg(0), f))).map(Character.init) ?? " "))
        case "read": return try LispInterpreter.read(s(0)).first ?? .nil_
        case "princ", "prin1", "print", "prompt":
            if let v = a.first { let t = f == "princ" || f == "prompt" ? LispInterpreter.text(v) : v.description; output.append(t); editor?.print(t); return v }
            return .sym("")
        case "terpri", "alert": if f == "alert" { output.append(s(0)); editor?.print(s(0)) }; return .nil_
        case "pi": return .real(.pi)
        case "polar":
            guard let p = arg(0).point else { throw LispError(message: "bad argument type: point") }
            return .pt(p + Vec2.polar(try num(arg(2), f), try num(arg(1), f)))
        case "distance": guard let p = arg(0).point, let q = arg(1).point else { throw LispError(message: "bad argument type: point") }; return .real(p.distance(to: q))
        case "angle": guard let p = arg(0).point, let q = arg(1).point else { throw LispError(message: "bad argument type: point") }; var ang = (q - p).angle; if ang < 0 { ang += 2 * .pi }; return .real(ang)
        case "inters":
            guard let p1 = arg(0).point, let p2 = arg(1).point, let p3 = arg(2).point, let p4 = arg(3).point else { throw LispError(message: "bad argument type: point") }
            let onSeg = a.count < 5 || !arg(4).isNil
            let x = onSeg ? GeometryOps.segmentIntersection(p1, p2, p3, p4) : GeometryOps.lineIntersection(p1, p2, p3, p4)
            return x.map { .pt($0) } ?? .nil_
        case "getvar":
            guard let ed = editor else { return .nil_ }
            let n = s(0).uppercased()
            if let v = ed.doc.variable(n) { return Double(v).map { v.contains(".") ? .real($0) : .int(Int($0)) } ?? .str(v) }
            switch n { case "CLAYER": return .str(ed.doc.currentLayer); case "DWGNAME": return .str(ed.fileURL?.lastPathComponent ?? "Drawing1.archi"); default: return .nil_ }
        case "setvar":
            guard let ed = editor else { return .nil_ }
            let n = s(0).uppercased()
            ed.transaction("SETVAR") { d in if n == "CLAYER" { d.ensureLayer(s(1)); d.currentLayer = s(1) } else { d.setVariable(n, LispInterpreter.text(arg(1))) } }
            return arg(1)
        case "command":
            guard let ed = editor else { return .nil_ }
            var tokens: [String] = []
            for v in a {
                switch v {
                case .str(let x): tokens.append(x.isEmpty ? "\"\"" : (x.contains(" ") ? "\"\(x)\"" : x))
                case .int, .real: tokens.append(fmt(v.number ?? 0, 8))
                case .list(let l) where l.count >= 2 && l.allSatisfy({ $0.number != nil }): tokens.append(l.prefix(2).map { fmt($0.number!, 8) }.joined(separator: ","))
                case .ename(let id): tokens.append("#\(id)")
                case .pickset(let ids): tokens.append(ids.map { "#\($0)" }.joined(separator: ","))
                case .nil_: tokens.append("\"\"")
                default: tokens.append(LispInterpreter.text(v))
                }
            }
            guard !tokens.isEmpty else { return .nil_ }
            let line = tokens.joined(separator: " ")
            await ed.waitIdle()
            _ = await ed.run(line)
            return .nil_
        case "entlast": return (editor?.doc.entities.last?.id ?? editor?.doc.elements.last?.id).map { .ename($0) } ?? .nil_
        case "entdel": if case .ename(let id) = arg(0), let ed = editor { ed.transaction("ENTDEL") { $0.remove(ids: [id]) } }; return arg(0)
        case "entget":
            guard case .ename(let id) = arg(0), let e = editor?.doc.entity(id) else { return .nil_ }
            return LispInterpreter.dxfList(e)
        case "entmod":
            guard let ed = editor, case .pair(.int(-1), .ename(let id)) = arg(0).items.first ?? .nil_, let i = ed.doc.entityIndex(id) else { return .nil_ }
            var e = ed.doc.entities[i]
            for item in arg(0).items {
                guard case .pair(.int(let code), let v) = item else {
                    if case .list(let l) = item, case .int(let code) = l.first, let p = LispValue.list(Array(l.dropFirst())).point {
                        switch (code, e.geometry) {
                        case (10, .line(var g)): g.a = p; e.geometry = .line(g)
                        case (11, .line(var g)): g.b = p; e.geometry = .line(g)
                        case (10, .circle(var g)): g.center = p; e.geometry = .circle(g)
                        case (10, .arc(var g)): g.center = p; e.geometry = .arc(g)
                        case (10, .point): e.geometry = .point(p)
                        case (10, .text(var g)): g.position = p; e.geometry = .text(g)
                        default: break
                        }
                    }
                    continue
                }
                switch (code, v) {
                case (8, .str(let l)): e.layer = l; if ed.doc.layer(named: l) == nil { ed.transaction("LAYER") { $0.ensureLayer(l) } }
                case (62, .int(let c)): e.color = .aci(c)
                case (40, _): if let r = v.number { if case .circle(var g) = e.geometry { g.radius = r; e.geometry = .circle(g) } else if case .arc(var g) = e.geometry { g.radius = r; e.geometry = .arc(g) } else if case .text(var g) = e.geometry { g.height = r; e.geometry = .text(g) } }
                case (1, .str(let t)): if case .text(var g) = e.geometry { g.content = t; e.geometry = .text(g) }
                default: break
                }
            }
            let modified = e
            ed.transaction("ENTMOD") { $0.entities[i] = modified }
            return arg(0)
        case "ssget":
            guard let ed = editor else { return .nil_ }
            var filter: [(Int, String)] = []
            let listArg = s(0) == "X" || s(0) == "x" ? arg(1) : (a.first.map { if case .list = $0 { return $0 }; return .nil_ } ?? .nil_)
            for item in listArg.items { if case .pair(.int(let c), .str(let v)) = item { filter.append((c, v.uppercased())) } }
            let wantAll = s(0).uppercased() == "X" || a.isEmpty || !filter.isEmpty
            var ids = wantAll ? ed.doc.entities.map(\.id) : Array(ed.selection).sorted()
            if a.isEmpty && !ed.selection.isEmpty { ids = Array(ed.selection).sorted() }
            ids = ids.filter { id in
                guard let e = ed.doc.entity(id) else { return filter.isEmpty }
                return filter.allSatisfy { c, v in
                    let pat = v.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    switch c { case 0: return pat.contains(LispInterpreter.dxfType(e)); case 8: return pat.contains(e.layer.uppercased()) || pat.contains("*"); default: return true }
                }
            }
            return ids.isEmpty ? .nil_ : .pickset(ids)
        case "sslength": if case .pickset(let s) = arg(0) { return .int(s.count) }; return .nil_
        case "ssname": if case .pickset(let s) = arg(0), let i = arg(1).number.map(Int.init), i >= 0, i < s.count { return .ename(s[i]) }; return .nil_
        case "mapcar":
            let lists = a.dropFirst().map(\.items)
            let n = lists.map(\.count).min() ?? 0
            var out: [LispValue] = []
            for i in 0..<n { out.append(try await apply(arg(0), lists.map { $0[i] })) }
            return .list(out)
        case "apply": return try await apply(arg(0), arg(1).items)
        case "getpoint", "getreal", "getint", "getstring", "getdist", "getangle", "getcorner", "getkword":
            editor?.print("(\(f)) needs interactive input, which LISP routines cannot ask for here; it returns nil.")
            return .nil_
        case "initget": return .nil_
        default: throw LispError(message: "no function definition: \(f.uppercased())")
        }
    }

    static func dxfType(_ e: Entity) -> String {
        switch e.geometry {
        case .polyline: return "LWPOLYLINE"
        case .text(let t): return t.width > 0 || t.content.contains("\n") ? "MTEXT" : "TEXT"
        case .solid: return "3DSOLID"
        default: return e.typeName.uppercased()
        }
    }
    static func dxfList(_ e: Entity) -> LispValue {
        var l: [LispValue] = [.pair(.int(-1), .ename(e.id)), .pair(.int(0), .str(dxfType(e))), .pair(.int(8), .str(e.layer))]
        if case .aci(let c) = e.color { l.append(.pair(.int(62), .int(c))) }
        switch e.geometry {
        case .line(let g): l += [.list([.int(10), .real(g.a.x), .real(g.a.y), .real(0)]), .list([.int(11), .real(g.b.x), .real(g.b.y), .real(0)])]
        case .circle(let g): l += [.list([.int(10), .real(g.center.x), .real(g.center.y), .real(0)]), .pair(.int(40), .real(g.radius))]
        case .arc(let g): l += [.list([.int(10), .real(g.center.x), .real(g.center.y), .real(0)]), .pair(.int(40), .real(g.radius)), .pair(.int(50), .real(g.start)), .pair(.int(51), .real(g.end))]
        case .point(let p): l += [.list([.int(10), .real(p.x), .real(p.y), .real(0)])]
        case .text(let t): l += [.list([.int(10), .real(t.position.x), .real(t.position.y), .real(0)]), .pair(.int(40), .real(t.height)), .pair(.int(1), .str(t.content))]
        case .polyline(let p):
            l.append(.pair(.int(90), .int(p.vertices.count))); l.append(.pair(.int(70), .int(p.closed ? 1 : 0)))
            for v in p.vertices { l.append(.list([.int(10), .real(v.p.x), .real(v.p.y)])) }
        case .insert(let i): l += [.pair(.int(2), .str(i.block)), .list([.int(10), .real(i.position.x), .real(i.position.y), .real(0)])]
        default: break
        }
        return .list(l)
    }

    /// Registers c:NAME as a command (unless a built-in has that name).
    func registerCommand(_ name: String, ed: Editor) {
        let reg = ed.registry
        if let existing = reg.lookup(name), existing.category != "LISP" { ed.print("; \(name) is a built-in command: C:\(name) is only callable as (c:\(name.lowercased()))."); return }
        reg.register(CommandDef(name, category: "LISP", summary: "AutoLISP command C:\(name).", modifies: false) { ed in
            let lisp = LispInterpreter.shared
            lisp.editor = ed
            let prev = ed.backgroundTask
            ed.backgroundTask = Task { @MainActor in
                await prev?.value
                await ed.waitIdle()
                do { _ = try await lisp.apply(lisp.globals["c:" + name.lowercased()] ?? .nil_, [], name: "C:" + name) }
                catch { ed.print((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            }
        })
    }

    nonisolated static var commands: [CommandDef] { [
        CommandDef("LISPLOAD", aliases: ["LOADLISP", "LSPLOAD"], category: "Scripting",
                   summary: "Loads an AutoLISP (.lsp) file: its (defun c:NAME …) functions become commands; runs after this command, each (command …) its own undo step.", modifies: false) { ed in
            let url = try await IOCommands.path(ed, "Enter .lsp file to load")
            guard let src = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { throw CommandError.invalid("Cannot read \(url.path).") }
            let lisp = LispInterpreter.shared
            lisp.editor = ed
            let prev = ed.backgroundTask
            ed.backgroundTask = Task { @MainActor in
                await prev?.value
                await ed.waitIdle()
                do { let v = try await lisp.run(src); ed.print("\(url.lastPathComponent) loaded: \(v)") }
                catch { ed.print("\(url.lastPathComponent): " + ((error as? LocalizedError)?.errorDescription ?? "\(error)")) }
            }
        },
        CommandDef("LISP", aliases: ["LISPEVAL", "EVALLISP"], category: "Scripting",
                   summary: "Evaluates an AutoLISP expression, e.g. LISP \"(command \\\"CIRCLE\\\" '(0 0) 500)\"; the result is printed.", modifies: false) { ed in
            guard let src = try await ed.getString("Enter AutoLISP expression"), !src.isEmpty else { return }
            let lisp = LispInterpreter.shared
            lisp.editor = ed
            let prev = ed.backgroundTask
            ed.backgroundTask = Task { @MainActor in
                await prev?.value
                await ed.waitIdle()
                do { ed.print(try await lisp.run(src).description) }
                catch { ed.print((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            }
        },
    ] }
}
