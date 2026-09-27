// Oanarina Archi Tool — GPL-3.0-or-later
// OpenSCAD-compatible CSG scripting (M3D-090/092/094): an interpreter for the OpenSCAD language subset used by most
// models — variables, expressions, vectors, ranges and list comprehensions, functions, modules with children(), if /
// for, cube / sphere / cylinder / polyhedron, square / circle / polygon, linear_extrude / rotate_extrude,
// translate / rotate / scale / mirror / multmatrix / resize / color, union / difference / intersection / hull /
// minkowski, offset / projection, include / use. Tessellation follows OpenSCAD's rules ($fn, $fa, $fs and its
// sphere/cylinder layouts) so meshes match the reference implementation. Independent implementation; OpenSCAD itself
// is GPL-2.0-or-later (https://openscad.org).
import Foundation

public enum SCAD {
    public struct Result {
        /// Union of the top-level 3D objects (closed triangle soup), empty when none.
        public var triangles: [Tri3] = []
        /// Top-level 2D shapes (even-odd loops).
        public var loops: [[Vec2]] = []
        public var echo: [String] = []
        public var errors: [String] = []
        public var solid: SolidGeom? { SolidPrimitives.solid(triangles) }
    }

    /// Evaluates a script. `loader` reads included / used files (path relative to the script).
    public static func evaluate(_ source: String, loader: ((String) -> String?)? = nil) -> Result {
        let interp = Interpreter(loader: loader)
        var res = Result()
        do {
            var parser = Parser(try Lexer.tokens(source), loader: loader)
            let prog = try parser.program()
            let geos = try interp.run(prog)
            var solids: [[Tri3]] = [], shapes: [[[Vec2]]] = []
            for g in geos { switch g { case .solid(let t): if !t.isEmpty { solids.append(t) }; case .shape(let l): if !l.isEmpty { shapes.append(l) }; case .empty: break } }
            res.triangles = Geo.unionAll(solids)
            res.loops = shapes.count == 1 ? shapes[0] : shapes.reduce([]) { PolygonBoolean.apply(.union, $0, $1) }
        } catch let e as SCADError { res.errors.append(e.message) } catch { res.errors.append("\(error)") }
        res.echo = interp.echo
        res.errors += interp.warnings
        return res
    }

    struct SCADError: Error { var message: String }

    // MARK: Values

    indirect enum Val: Equatable {
        case num(Double), bool(Bool), str(String), vec([Val]), range(Double, Double, Double), undef
        var num: Double? { if case .num(let d) = self { return d }; if case .bool(let b) = self { return b ? 1 : 0 }; return nil }
        var truthy: Bool {
            switch self { case .num(let d): return d != 0; case .bool(let b): return b; case .str(let s): return !s.isEmpty; case .vec(let v): return !v.isEmpty; case .range: return true; case .undef: return false }
        }
        var list: [Val]? {
            switch self {
            case .vec(let v): return v
            case .range(let a, let s, let b):
                guard s != 0, (b - a) / s >= 0 || abs(b - a) < 1e-12 else { return [] }
                let n = Int(((b - a) / s + 1e-9).rounded(.down))
                guard n < 1_000_000 else { return nil }
                return (0...max(n, 0)).map { .num(a + Double($0) * s) }
            default: return nil
            }
        }
        var vec3: Vec3? {
            guard let l = list, l.count >= 2, let x = l[0].num, let y = l[1].num else { return nil }
            return Vec3(x, y, l.count > 2 ? (l[2].num ?? 0) : 0)
        }
        var description: String {
            switch self {
            case .num(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
            case .bool(let b): return b ? "true" : "false"
            case .str(let s): return "\"\(s)\""
            case .vec(let v): return "[" + v.map(\.description).joined(separator: ", ") + "]"
            case .range(let a, let s, let b): return "[\(a) : \(s) : \(b)]"
            case .undef: return "undef"
            }
        }
    }

    // MARK: Geometry

    enum Geo {
        case solid([Tri3]), shape([[Vec2]]), empty
        static func unionAll(_ parts: [[Tri3]]) -> [Tri3] {
            guard var acc = parts.first else { return [] }
            for p in parts.dropFirst() {
                let ba = bounds(acc), bb = bounds(p)
                acc = ba.intersects3(bb) ? CSG.apply(.union, acc, p) : acc + p
            }
            return acc
        }
        static func bounds(_ t: [Tri3]) -> BBox3 { var b = BBox3.empty; for x in t { b.add(x.0); b.add(x.1); b.add(x.2) }; return b }
    }

    // MARK: Lexer

    enum Tok: Equatable { case num(Double), str(String), id(String), sym(String), eof }

    enum Lexer {
        static func tokens(_ s: String) throws -> [Tok] {
            let c = Array(s)
            var i = 0
            var out: [Tok] = []
            let two = ["<=", ">=", "==", "!=", "&&", "||"]
            while i < c.count {
                let ch = c[i]
                if ch.isWhitespace { i += 1; continue }
                if ch == "/" && i + 1 < c.count && c[i + 1] == "/" { while i < c.count && c[i] != "\n" { i += 1 }; continue }
                if ch == "/" && i + 1 < c.count && c[i + 1] == "*" {
                    i += 2
                    while i + 1 < c.count && !(c[i] == "*" && c[i + 1] == "/") { i += 1 }
                    i += 2; continue
                }
                if ch.isNumber || (ch == "." && i + 1 < c.count && c[i + 1].isNumber) {
                    var j = i
                    while j < c.count && (c[j].isNumber || c[j] == ".") { j += 1 }
                    if j < c.count && (c[j] == "e" || c[j] == "E") {
                        var k = j + 1
                        if k < c.count && (c[k] == "+" || c[k] == "-") { k += 1 }
                        if k < c.count && c[k].isNumber { j = k; while j < c.count && c[j].isNumber { j += 1 } }
                    }
                    guard let v = Double(String(c[i..<j])) else { throw SCADError(message: "Bad number at \(i)") }
                    out.append(.num(v)); i = j; continue
                }
                if ch.isLetter || ch == "_" || ch == "$" {
                    var j = i + 1
                    while j < c.count && (c[j].isLetter || c[j].isNumber || c[j] == "_") { j += 1 }
                    out.append(.id(String(c[i..<j]))); i = j; continue
                }
                if ch == "\"" {
                    var j = i + 1, v = ""
                    while j < c.count && c[j] != "\"" {
                        if c[j] == "\\" && j + 1 < c.count { j += 1; v.append(c[j] == "n" ? "\n" : c[j]) } else { v.append(c[j]) }
                        j += 1
                    }
                    out.append(.str(v)); i = j + 1; continue
                }
                if ch == "<" {
                    // include <file> / use <file>
                    if case .id(let k)? = out.last, k == "include" || k == "use", let close = c[i...].firstIndex(of: ">") {
                        out.append(.str(String(c[(i + 1)..<close]))); i = close + 1; continue
                    }
                }
                if i + 1 < c.count, two.contains(String([ch, c[i + 1]])) { out.append(.sym(String([ch, c[i + 1]]))); i += 2; continue }
                out.append(.sym(String(ch))); i += 1
            }
            out.append(.eof)
            return out
        }
    }

    // MARK: AST

    indirect enum Expr {
        case lit(Val), id(String), vec([Expr]), range(Expr, Expr?, Expr), bin(String, Expr, Expr), un(String, Expr), tern(Expr, Expr, Expr)
        case call(String, [Arg]), index(Expr, Expr), member(Expr, String), comp(vars: [(String, Expr)], cond: Expr?, body: Expr), letE([(String, Expr)], Expr)
    }
    struct Arg { var name: String?; var value: Expr }
    struct Param { var name: String; var def: Expr? }
    indirect enum Stmt {
        case assign(String, Expr)
        case call(name: String, args: [Arg], children: [Stmt], modifier: Character?)
        case block([Stmt])
        case module(String, [Param], [Stmt])
        case function(String, [Param], Expr)
        case ifS(Expr, [Stmt], [Stmt])
        case forS([(String, Expr)], [Stmt], intersect: Bool)
        case empty
    }

    // MARK: Parser

    struct Parser {
        var t: [Tok]; var i = 0
        let loader: ((String) -> String?)?
        init(_ t: [Tok], loader: ((String) -> String?)?) { self.t = t; self.loader = loader }
        var cur: Tok { t[i] }
        mutating func next() -> Tok { let x = t[i]; if i < t.count - 1 { i += 1 }; return x }
        func isSym(_ s: String) -> Bool { cur == .sym(s) }
        mutating func eat(_ s: String) -> Bool { if isSym(s) { i += 1; return true }; return false }
        mutating func expect(_ s: String) throws { guard eat(s) else { throw SCADError(message: "Expected '\(s)' near token \(i) (\(cur))") } }
        mutating func ident() throws -> String { guard case .id(let n) = next() else { throw SCADError(message: "Expected a name near token \(i)") }; return n }

        mutating func program() throws -> [Stmt] {
            var out: [Stmt] = []
            while cur != .eof { out += try statementWithIncludes() }
            return out
        }

        mutating func statementWithIncludes() throws -> [Stmt] {
            if case .id(let k) = cur, k == "include" || k == "use" {
                _ = next()
                guard case .str(let path) = next() else { throw SCADError(message: "\(k) needs <file>") }
                guard let src = loader?(path) else { throw SCADError(message: "Cannot read \(path)") }
                var p = Parser(try Lexer.tokens(src), loader: loader)
                let body = try p.program()
                // use<> imports only modules and functions.
                return k == "use" ? body.filter { if case .module = $0 { return true }; if case .function = $0 { return true }; return false } : body
            }
            return [try statement()]
        }

        mutating func statement() throws -> Stmt {
            if eat(";") { return .empty }
            if eat("{") {
                var b: [Stmt] = []
                while !eat("}") { guard cur != .eof else { throw SCADError(message: "Missing }") }; b += try statementWithIncludes() }
                return .block(b)
            }
            var modifier: Character? = nil
            if case .sym(let s) = cur, ["#", "%", "*", "!"].contains(s) { modifier = s.first; _ = next() }
            guard case .id(let name) = cur else { throw SCADError(message: "Unexpected \(cur) near token \(i)") }
            if name == "module" {
                _ = next(); let n = try ident(); let ps = try params()
                let body = try statement()
                if case .block(let b) = body { return .module(n, ps, b) }
                return .module(n, ps, [body])
            }
            if name == "function" {
                _ = next(); let n = try ident(); let ps = try params(); try expect("=")
                let e = try expr(); _ = eat(";")
                return .function(n, ps, e)
            }
            if name == "if" {
                _ = next(); try expect("("); let c = try expr(); try expect(")")
                let a = try statement()
                var b: Stmt = .empty
                if case .id("else") = cur { _ = next(); b = try statement() }
                func list(_ s: Stmt) -> [Stmt] { if case .block(let x) = s { return x }; return [s] }
                return .ifS(c, list(a), list(b))
            }
            if name == "for" || name == "intersection_for" {
                _ = next(); try expect("(")
                var vars: [(String, Expr)] = []
                repeat { let n = try ident(); try expect("="); vars.append((n, try expr())) } while eat(",")
                try expect(")")
                let body = try statement()
                if case .block(let b) = body { return .forS(vars, b, intersect: name == "intersection_for") }
                return .forS(vars, [body], intersect: name == "intersection_for")
            }
            // Assignment or module call.
            if t[i + 1] == .sym("=") {
                _ = next(); _ = next(); let e = try expr(); try expect(";")
                return .assign(name, e)
            }
            _ = next()
            try expect("(")
            let a = try args()
            var children: [Stmt] = []
            if eat(";") {} else {
                let c = try statement()
                if case .block(let b) = c { children = b } else { children = [c] }
            }
            return .call(name: name, args: a, children: children, modifier: modifier)
        }

        mutating func params() throws -> [Param] {
            try expect("(")
            var ps: [Param] = []
            while !eat(")") {
                let n = try ident()
                var d: Expr? = nil
                if eat("=") { d = try expr() }
                ps.append(Param(name: n, def: d))
                _ = eat(",")
            }
            return ps
        }

        /// Arguments after "(" up to ")".
        mutating func args() throws -> [Arg] {
            var out: [Arg] = []
            while !eat(")") {
                if case .id(let n) = cur, t[i + 1] == .sym("=") { _ = next(); _ = next(); out.append(Arg(name: n, value: try expr())) }
                else { out.append(Arg(name: nil, value: try expr())) }
                if !eat(",") { try expect(")"); break }
            }
            return out
        }

        mutating func expr() throws -> Expr {
            if case .id("let") = cur, t[i + 1] == .sym("(") {
                _ = next(); _ = next()
                var vs: [(String, Expr)] = []
                while !eat(")") { let n = try ident(); try expect("="); vs.append((n, try expr())); _ = eat(",") }
                return .letE(vs, try expr())
            }
            let c = try binary(0)
            if eat("?") { let a = try expr(); try expect(":"); let b = try expr(); return .tern(c, a, b) }
            return c
        }

        static let prec: [String: Int] = ["||": 1, "&&": 2, "==": 3, "!=": 3, "<": 4, "<=": 4, ">": 4, ">=": 4, "+": 5, "-": 5, "*": 6, "/": 6, "%": 6, "^": 7]

        mutating func binary(_ minP: Int) throws -> Expr {
            var lhs = try unary()
            while case .sym(let op) = cur, let p = Parser.prec[op], p > minP {
                _ = next()
                let rhs = try binary(op == "^" ? p - 1 : p)
                lhs = .bin(op, lhs, rhs)
            }
            return lhs
        }

        mutating func unary() throws -> Expr {
            if eat("-") { return .un("-", try unary()) }
            if eat("+") { return try unary() }
            if eat("!") { return .un("!", try unary()) }
            return try postfix()
        }

        mutating func postfix() throws -> Expr {
            var e = try primary()
            while true {
                if eat("[") { let k = try expr(); try expect("]"); e = .index(e, k) }
                else if eat(".") { e = .member(e, try ident()) }
                else { break }
            }
            return e
        }

        mutating func primary() throws -> Expr {
            switch next() {
            case .num(let d): return .lit(.num(d))
            case .str(let s): return .lit(.str(s))
            case .id(let n):
                switch n {
                case "true": return .lit(.bool(true))
                case "false": return .lit(.bool(false))
                case "undef": return .lit(.undef)
                case "PI": return .lit(.num(.pi))
                default: break
                }
                if eat("(") { return .call(n, try args()) }
                return .id(n)
            case .sym("("):
                let e = try expr(); try expect(")"); return e
            case .sym("["):
                if eat("]") { return .vec([]) }
                if case .id("for") = cur {
                    _ = next(); try expect("(")
                    var vars: [(String, Expr)] = []
                    repeat { let n = try ident(); try expect("="); vars.append((n, try expr())) } while eat(",")
                    try expect(")")
                    var cond: Expr? = nil
                    if case .id("if") = cur { _ = next(); try expect("("); cond = try expr(); try expect(")") }
                    let body = try expr()
                    try expect("]")
                    return .comp(vars: vars, cond: cond, body: body)
                }
                let first = try expr()
                if eat(":") {
                    let second = try expr()
                    if eat(":") { let third = try expr(); try expect("]"); return .range(first, second, third) }
                    try expect("]"); return .range(first, nil, second)
                }
                var items = [first]
                while eat(",") { if isSym("]") { break }; items.append(try expr()) }
                try expect("]")
                return .vec(items)
            default: throw SCADError(message: "Unexpected token near \(i)")
            }
        }
    }

    // MARK: Interpreter

    final class Env {
        var vars: [String: Val] = [:]
        var modules: [String: (params: [Param], body: [Stmt], env: Env)] = [:]
        var functions: [String: (params: [Param], body: Expr, env: Env)] = [:]
        let parent: Env?
        var children: (stmts: [Stmt], env: Env)?
        init(_ p: Env?) { parent = p }
        func get(_ n: String) -> Val? { vars[n] ?? parent?.get(n) }
        func module(_ n: String) -> (params: [Param], body: [Stmt], env: Env)? { modules[n] ?? parent?.module(n) }
        func function(_ n: String) -> (params: [Param], body: Expr, env: Env)? { functions[n] ?? parent?.function(n) }
        var childBlock: (stmts: [Stmt], env: Env)? { children ?? parent?.childBlock }
    }

    final class Interpreter {
        let loader: ((String) -> String?)?
        var echo: [String] = []
        var warnings: [String] = []
        var depth = 0
        init(loader: ((String) -> String?)?) { self.loader = loader }

        func run(_ prog: [Stmt]) throws -> [Geo] {
            let g = Env(nil)
            g.vars["$fn"] = .num(0); g.vars["$fa"] = .num(12); g.vars["$fs"] = .num(2)
            return try exec(prog, g)
        }

        /// Executes a block: modules/functions are hoisted, assignments run in order, geometry is collected.
        func exec(_ stmts: [Stmt], _ env: Env) throws -> [Geo] {
            for s in stmts {
                if case .module(let n, let ps, let b) = s { env.modules[n] = (ps, b, env) }
                if case .function(let n, let ps, let e) = s { env.functions[n] = (ps, e, env) }
            }
            var out: [Geo] = []
            for s in stmts {
                switch s {
                case .assign(let n, let e): env.vars[n] = try eval(e, env)
                case .block(let b): out += try exec(b, Env(env))
                case .ifS(let c, let a, let b): out += try exec(try eval(c, env).truthy ? a : b, Env(env))
                case .forS(let vars, let body, let inter):
                    var parts: [Geo] = []
                    try iterate(vars, env) { e in parts.append(contentsOf: try self.exec(body, e)) }
                    out += inter ? [try boolean("intersection", parts)] : parts
                case .call(let name, let args, let children, let mod):
                    if mod == "*" || mod == "%" { continue }
                    out += try call(name, args, children, env)
                default: break
                }
            }
            return out
        }

        func iterate(_ vars: [(String, Expr)], _ env: Env, _ body: (Env) throws -> Void) throws {
            guard let (n, e) = vars.first else { return }
            let v = try eval(e, env)
            guard let items = v.list ?? (v == .undef ? [] : [v]) as [Val]? else { throw SCADError(message: "for: range too large") }
            for it in items {
                let inner = Env(env); inner.vars[n] = it
                if vars.count == 1 { try body(inner) } else { try iterate(Array(vars.dropFirst()), inner, body) }
            }
        }

        // MARK: Expressions

        func eval(_ e: Expr, _ env: Env) throws -> Val {
            switch e {
            case .lit(let v): return v
            case .id(let n): return env.get(n) ?? .undef
            case .vec(let items): return .vec(try items.map { try eval($0, env) })
            case .range(let a, let s, let b):
                guard let x = try eval(a, env).num, let y = try eval(b, env).num else { return .undef }
                let st = try s.map { try eval($0, env).num ?? 1 } ?? 1
                return .range(x, st, y)
            case .un(let op, let a):
                let v = try eval(a, env)
                if op == "!" { return .bool(!v.truthy) }
                if let d = v.num { return .num(-d) }
                if let l = v.list { return .vec(try l.map { try negate($0) }) }
                return .undef
            case .tern(let c, let a, let b): return try eval(try eval(c, env).truthy ? a : b, env)
            case .bin(let op, let a, let b):
                if op == "&&" { return .bool(try eval(a, env).truthy && eval(b, env).truthy) }
                if op == "||" { return .bool(try eval(a, env).truthy || eval(b, env).truthy) }
                return try binop(op, try eval(a, env), try eval(b, env))
            case .index(let a, let k):
                let v = try eval(a, env), ix = try eval(k, env)
                guard let i = ix.num.map({ Int($0) }) else { return .undef }
                if case .str(let s) = v { let c = Array(s); return i >= 0 && i < c.count ? .str(String(c[i])) : .undef }
                guard let l = v.list, i >= 0, i < l.count else { return .undef }
                return l[i]
            case .member(let a, let m):
                guard let l = try eval(a, env).list else { return .undef }
                let k = ["x": 0, "y": 1, "z": 2][m] ?? -1
                return k >= 0 && k < l.count ? l[k] : .undef
            case .comp(let vars, let cond, let body):
                var out: [Val] = []
                try iterate(vars, env) { inner in
                    if let c = cond, !(try self.eval(c, inner).truthy) { return }
                    out.append(try self.eval(body, inner))
                }
                return .vec(out)
            case .letE(let vs, let body):
                let inner = Env(env)
                for (n, x) in vs { inner.vars[n] = try eval(x, inner) }
                return try eval(body, inner)
            case .call(let n, let args): return try callFunction(n, args, env)
            }
        }

        func negate(_ v: Val) throws -> Val { if let d = v.num { return .num(-d) }; if let l = v.list { return .vec(try l.map(negate)) }; return .undef }

        func binop(_ op: String, _ a: Val, _ b: Val) throws -> Val {
            switch op {
            case "==": return .bool(a == b || (a.num != nil && a.num == b.num))
            case "!=": return .bool(!(a == b || (a.num != nil && a.num == b.num)))
            case "<", "<=", ">", ">=":
                if let x = a.num, let y = b.num { return .bool(op == "<" ? x < y : op == "<=" ? x <= y : op == ">" ? x > y : x >= y) }
                if case .str(let x) = a, case .str(let y) = b { return .bool(op == "<" ? x < y : op == "<=" ? x <= y : op == ">" ? x > y : x >= y) }
                return .undef
            default: break
            }
            if let x = a.num, let y = b.num {
                switch op {
                case "+": return .num(x + y)
                case "-": return .num(x - y)
                case "*": return .num(x * y)
                case "/": return .num(x / y)
                case "%": return .num(x.truncatingRemainder(dividingBy: y))
                case "^": return .num(pow(x, y))
                default: return .undef
                }
            }
            if let l = a.list, let r = b.list {
                switch op {
                case "+", "-": return .vec(try zip(l, r).map { try binop(op, $0.0, $0.1) })
                case "*":
                    // Dot product of vectors, or matrix products.
                    if l.allSatisfy({ $0.num != nil }) && r.allSatisfy({ $0.num != nil }) { return .num(zip(l, r).reduce(0) { $0 + $1.0.num! * $1.1.num! }) }
                    if l.allSatisfy({ $0.list != nil }) && r.allSatisfy({ $0.num != nil }) { return .vec(try l.map { try binop("*", $0, b) }) }
                    if l.allSatisfy({ $0.num != nil }), let rows = r.first?.list?.count, r.allSatisfy({ $0.list != nil }) {
                        return .vec((0..<rows).map { j in .num(zip(l, r).reduce(0) { $0 + $1.0.num! * ($1.1.list![j].num ?? 0) }) })
                    }
                    if l.allSatisfy({ $0.list != nil }), r.allSatisfy({ $0.list != nil }) {
                        let cols = r.first?.list?.count ?? 0
                        return .vec(l.map { row in .vec((0..<cols).map { j in .num(zip(row.list!, r).reduce(0) { $0 + ($1.0.num ?? 0) * ($1.1.list![j].num ?? 0) }) }) })
                    }
                    return .undef
                default: return .undef
                }
            }
            if let l = a.list, b.num != nil, op == "*" || op == "/" { return .vec(try l.map { try binop(op, $0, b) }) }
            if let r = b.list, a.num != nil, op == "*" { return .vec(try r.map { try binop(op, a, $0) }) }
            return .undef
        }

        func bind(_ params: [Param], _ args: [Arg], callerEnv: Env, into env: Env) throws {
            var positional = 0
            for a in args {
                let v = try eval(a.value, callerEnv)
                if let n = a.name { env.vars[n] = v }
                else if positional < params.count { env.vars[params[positional].name] = v; positional += 1 }
            }
            for p in params where env.vars[p.name] == nil { env.vars[p.name] = try p.def.map { try eval($0, env) } ?? .undef }
        }

        func callFunction(_ n: String, _ args: [Arg], _ env: Env) throws -> Val {
            if let f = env.function(n) {
                depth += 1; defer { depth -= 1 }
                guard depth < 2000 else { throw SCADError(message: "Recursion too deep in \(n)") }
                let inner = Env(f.env)
                try bind(f.params, args, callerEnv: env, into: inner)
                return try eval(f.body, inner)
            }
            let v = try args.map { try eval($0.value, env) }
            func d(_ i: Int) -> Double? { i < v.count ? v[i].num : nil }
            let r = Double.pi / 180
            switch n {
            case "sin": return d(0).map { .num(sin($0 * r)) } ?? .undef
            case "cos": return d(0).map { .num(cos($0 * r)) } ?? .undef
            case "tan": return d(0).map { .num(tan($0 * r)) } ?? .undef
            case "asin": return d(0).map { .num(asin($0) / r) } ?? .undef
            case "acos": return d(0).map { .num(acos($0) / r) } ?? .undef
            case "atan": return d(0).map { .num(atan($0) / r) } ?? .undef
            case "atan2": if let y = d(0), let x = d(1) { return .num(atan2(y, x) / r) }; return .undef
            case "sqrt": return d(0).map { .num($0.squareRoot()) } ?? .undef
            case "abs": return d(0).map { .num(abs($0)) } ?? .undef
            case "floor": return d(0).map { .num($0.rounded(.down)) } ?? .undef
            case "ceil": return d(0).map { .num($0.rounded(.up)) } ?? .undef
            case "round": return d(0).map { .num($0.rounded()) } ?? .undef
            case "sign": return d(0).map { .num($0 > 0 ? 1 : ($0 < 0 ? -1 : 0)) } ?? .undef
            case "exp": return d(0).map { .num(Foundation.exp($0)) } ?? .undef
            case "ln": return d(0).map { .num(Foundation.log($0)) } ?? .undef
            case "log": return d(0).map { .num(log10($0)) } ?? .undef
            case "pow": if let a = d(0), let b = d(1) { return .num(pow(a, b)) }; return .undef
            case "min", "max":
                let xs = (v.count == 1 ? (v[0].list ?? v) : v).compactMap(\.num)
                guard !xs.isEmpty else { return .undef }
                return .num(n == "min" ? xs.min()! : xs.max()!)
            case "len":
                if case .str(let s)? = v.first { return .num(Double(s.count)) }
                return v.first?.list.map { .num(Double($0.count)) } ?? .undef
            case "norm":
                guard let l = v.first?.list else { return .undef }
                return .num(l.compactMap(\.num).reduce(0) { $0 + $1 * $1 }.squareRoot())
            case "cross":
                guard let a = v.first?.vec3, v.count > 1, let b = v[1].vec3 else { return .undef }
                let c = a.cross(b); return .vec([.num(c.x), .num(c.y), .num(c.z)])
            case "concat": return .vec(v.flatMap { $0.list ?? [$0] })
            case "str": return .str(v.map { if case .str(let s) = $0 { return s }; return $0.description }.joined())
            case "is_undef": return .bool(v.first == .undef)
            case "is_num": return .bool(v.first?.num != nil && { if case .num = v.first! { return true }; return false }())
            case "is_list": return .bool(v.first?.list != nil)
            case "lookup":
                guard let k = d(0), v.count > 1, let tbl = v[1].list?.compactMap({ $0.list }), !tbl.isEmpty else { return .undef }
                let pts = tbl.compactMap { p -> (Double, Double)? in p.count >= 2 ? (p[0].num ?? 0, p[1].num ?? 0) : nil }.sorted { $0.0 < $1.0 }
                if k <= pts[0].0 { return .num(pts[0].1) }
                if k >= pts.last!.0 { return .num(pts.last!.1) }
                for i in 0..<(pts.count - 1) where k <= pts[i + 1].0 { let t = (k - pts[i].0) / (pts[i + 1].0 - pts[i].0); return .num(pts[i].1 + (pts[i + 1].1 - pts[i].1) * t) }
                return .undef
            case "echo": echo.append(v.map(\.description).joined(separator: ", ")); return .undef
            default:
                warnings.append("Unknown function \(n)")
                return .undef
            }
        }

        // MARK: Module calls

        func arg(_ args: [Arg], _ env: Env, _ name: String, _ pos: Int?) throws -> Val? {
            if let a = args.first(where: { $0.name == name }) { return try eval(a.value, env) }
            let positional = args.filter { $0.name == nil }
            if let p = pos, p < positional.count { return try eval(positional[p].value, env) }
            return nil
        }

        /// Fragments for a radius (OpenSCAD get_fragments_from_r).
        static func fragments(_ r: Double, _ env: Env) -> Int {
            let fn = env.get("$fn")?.num ?? 0, fs = env.get("$fs")?.num ?? 2, fa = env.get("$fa")?.num ?? 12
            if r < 1e-9 { return 3 }
            if fn > 0 { return max(Int(fn), 3) }
            return Int(max(min(360 / fa, r * 2 * .pi / fs), 5).rounded(.up))
        }

        func call(_ name: String, _ args: [Arg], _ children: [Stmt], _ env: Env) throws -> [Geo] {
            // Special variables passed as arguments apply to the call.
            let callEnv = Env(env)
            for a in args where a.name?.hasPrefix("$") == true { callEnv.vars[a.name!] = try eval(a.value, env) }
            let me = self
            func A(_ n: String, _ p: Int? = nil) throws -> Val? { try me.arg(args, env, n, p) }
            func kids() throws -> [Geo] { try me.exec(children, Env(callEnv)) }
            switch name {
            case "echo":
                me.echo.append(try args.map { a in (a.name.map { "\($0) = " } ?? "") + (try me.eval(a.value, env)).description }.joined(separator: ", "))
                return []
            case "children":
                guard let cb = env.childBlock else { return [] }
                let all = cb.stmts.filter { if case .assign = $0 { return false }; if case .module = $0 { return false }; if case .function = $0 { return false }; return true }
                if let idx = try A("index", 0) {
                    let ids = idx.list?.compactMap(\.num) ?? [idx.num ?? 0]
                    return try ids.flatMap { i -> [Geo] in let k = Int(i); return k >= 0 && k < all.count ? try me.exec([all[k]], Env(cb.env)) : [] }
                }
                return try me.exec(cb.stmts, Env(cb.env))
            case "cube":
                let sv = try A("size", 0) ?? .num(1)
                let s = sv.vec3 ?? Vec3(sv.num ?? 1, sv.num ?? 1, sv.num ?? 1)
                let c = try A("center", 1)?.truthy ?? false
                guard s.x > 0, s.y > 0, s.z > 0 else { return [] }
                let o = c ? s / -2 : Vec3.zero
                return [.solid(Prims.box(o, s))]
            case "sphere":
                var r = try A("r", 0)?.num ?? 1
                if let d = try A("d")?.num { r = d / 2 }
                guard r > 0 else { return [] }
                return [.solid(Prims.sphere(r, Interpreter.fragments(r, callEnv)))]
            case "cylinder":
                let h = try A("h", 0)?.num ?? 1
                var r1 = try A("r1", 1)?.num ?? 1, r2 = try A("r2", 2)?.num ?? 1
                if let r = try A("r")?.num { r1 = r; r2 = r }
                if let d = try A("d")?.num { r1 = d / 2; r2 = d / 2 }
                if let d = try A("d1")?.num { r1 = d / 2 }
                if let d = try A("d2")?.num { r2 = d / 2 }
                let c = try A("center")?.truthy ?? false
                guard h > 0, r1 >= 0, r2 >= 0, r1 + r2 > 0 else { return [] }
                return [.solid(Prims.cylinder(h: h, r1: r1, r2: r2, center: c, n: Interpreter.fragments(max(r1, r2), callEnv)))]
            case "polyhedron":
                guard let pts = try A("points", 0)?.list?.compactMap({ $0.vec3 }), let fs = try (A("faces", 1) ?? A("triangles"))?.list else { return [] }
                var tris: [Tri3] = []
                for f in fs {
                    let idx = (f.list ?? []).compactMap { $0.num.map(Int.init) }.filter { $0 >= 0 && $0 < pts.count }
                    guard idx.count >= 3 else { continue }
                    // OpenSCAD faces are clockwise seen from outside.
                    let poly = idx.reversed().map { pts[$0] }
                    tris += SolidPrimitives.polygon(poly, normal: Mesh.polygonNormal(poly))
                }
                return [.solid(tris)]
            case "square":
                let sv = try A("size", 0) ?? .num(1)
                let s = sv.vec3.map { Vec2($0.x, $0.y) } ?? Vec2(sv.num ?? 1, sv.num ?? 1)
                let c = try A("center", 1)?.truthy ?? false
                let o = c ? s / -2 : Vec2.zero
                return [.shape([[o, o + Vec2(s.x, 0), o + s, o + Vec2(0, s.y)]])]
            case "circle":
                var r = try A("r", 0)?.num ?? 1
                if let d = try A("d")?.num { r = d / 2 }
                guard r > 0 else { return [] }
                let n = Interpreter.fragments(r, callEnv)
                return [.shape([(0..<n).map { Vec2.polar(r, 2 * .pi * Double($0) / Double(n)) }])]
            case "polygon":
                guard let pts = try A("points", 0)?.list?.compactMap({ $0.vec3.map { Vec2($0.x, $0.y) } }) else { return [] }
                if let paths = try A("paths", 1)?.list {
                    var rings: [[Vec2]] = []
                    for p in paths {
                        guard let items = p.list else { continue }
                        let idx: [Int] = items.compactMap { $0.num.map(Int.init) }.filter { $0 >= 0 && $0 < pts.count }
                        let ring: [Vec2] = idx.map { pts[$0] }
                        if ring.count >= 3 { rings.append(ring) }
                    }
                    return [.shape(rings)]
                }
                return [.shape([pts])]
            case "translate", "rotate", "scale", "mirror", "multmatrix", "resize", "color":
                var m = Mat.identity
                switch name {
                case "translate": if let v = try A("v", 0)?.vec3 { m = Mat.translation(v) }
                case "scale":
                    let v = try A("v", 0)
                    if let s = v?.vec3 { m = Mat.scale(Vec3(s.x, s.y, (v?.list?.count ?? 3) > 2 ? s.z : 1)) } else if let k = v?.num { m = Mat.scale(Vec3(k, k, k)) }
                case "rotate":
                    let a = try A("a", 0)
                    if let v = try A("v", 1)?.vec3, let ang = a?.num { m = Mat.axisAngle(v, ang) }
                    else if let r = a?.vec3 { m = Mat.rotZ(r.z) * Mat.rotY(r.y) * Mat.rotX(r.x) }
                    else if let ang = a?.num { m = Mat.rotZ(ang) }
                case "mirror": if let v = try A("v", 0)?.vec3 { m = Mat.mirror(v) }
                case "multmatrix":
                    if let rows = try A("m", 0)?.list?.compactMap({ $0.list?.compactMap(\.num) }), rows.count >= 3, rows.allSatisfy({ $0.count >= 4 }) {
                        m = Mat(rows: rows.prefix(3).map { Array($0.prefix(4)) })
                    }
                case "resize":
                    let g = try kids()
                    guard let target = try A("newsize", 0)?.vec3 else { return g }
                    var b = BBox3.empty
                    for x in g { if case .solid(let t) = x { for q in t { b.add(q.0); b.add(q.1); b.add(q.2) } }; if case .shape(let l) = x { for q in l.joined() { b.add(Vec3(q.x, q.y, 0)) } } }
                    guard !b.isEmpty else { return g }
                    func f(_ want: Double, _ have: Double) -> Double { want > 0 && have > 1e-12 ? want / have : 1 }
                    m = Mat.scale(Vec3(f(target.x, b.size.x), f(target.y, b.size.y), f(target.z, b.size.z)))
                    return g.map { Prims.transform($0, m) }
                default: break
                }
                return try kids().map { Prims.transform($0, m) }
            case "union", "difference", "intersection", "hull", "minkowski", "group", "render":
                let g = try kids()
                if name == "group" || name == "render" { return g }
                return [try me.boolean(name, g)]
            case "linear_extrude":
                let h = try A("height", 0)?.num ?? 100
                let c = try A("center")?.truthy ?? false
                let tw = try A("twist")?.num ?? 0
                let sc = try A("scale")?.num ?? (try A("scale")?.vec3?.x ?? 1)
                let sl = Int(try A("slices")?.num ?? 0)
                let loops = try kids().flatMap { g -> [[Vec2]] in if case .shape(let l) = g { return l }; return [] }
                return [.solid(Prims.linearExtrude(loops, h: h, center: c, twist: tw, scale: sc, slices: sl))]
            case "rotate_extrude":
                let ang = try A("angle")?.num ?? 360
                let loops = try kids().flatMap { g -> [[Vec2]] in if case .shape(let l) = g { return l }; return [] }
                let maxX = loops.joined().map(\.x).max() ?? 1
                return [.solid(Prims.rotateExtrude(loops, angle: ang, n: Interpreter.fragments(maxX, callEnv)))]
            case "offset":
                let r = try A("r", 0)?.num, dl = try A("delta")?.num
                let d = r ?? dl ?? 0
                let loops = try kids().flatMap { g -> [[Vec2]] in if case .shape(let l) = g { return l }; return [] }
                return [.shape(Prims.offset(loops, d, round: r != nil, n: Interpreter.fragments(abs(d), callEnv)))]
            case "projection":
                let cut = try A("cut", 0)?.truthy ?? false
                let tris = try kids().flatMap { g -> [Tri3] in if case .solid(let t) = g { return t }; return [] }
                return [.shape(Prims.projection(tris, cut: cut))]
            default:
                guard let mod = env.module(name) else { me.warnings.append("Unknown module \(name)"); return [] }
                me.depth += 1
                defer { me.depth -= 1 }
                guard me.depth < 500 else { throw SCADError(message: "Recursion too deep in \(name)") }
                let inner = Env(mod.env)
                for (k, v) in callEnv.vars { inner.vars[k] = v }
                try me.bind(mod.params, args.filter { !($0.name?.hasPrefix("$") ?? false) }, callerEnv: env, into: inner)
                inner.children = (children, callEnv)
                return try me.exec(mod.body, inner)
            }
        }

        func boolean(_ op: String, _ g: [Geo]) throws -> Geo {
            let solids = g.compactMap { x -> [Tri3]? in if case .solid(let t) = x, !t.isEmpty { return t }; return nil }
            let shapes = g.compactMap { x -> [[Vec2]]? in if case .shape(let l) = x, !l.isEmpty { return l }; return nil }
            if !solids.isEmpty {
                switch op {
                case "union": return .solid(Geo.unionAll(solids))
                case "difference":
                    var acc = solids[0]
                    for s in solids.dropFirst() where Geo.bounds(acc).intersects3(Geo.bounds(s)) { acc = CSG.apply(.subtract, acc, s) }
                    return .solid(acc)
                case "intersection":
                    var acc = solids[0]
                    for s in solids.dropFirst() { acc = CSG.apply(.intersect, acc, s); if acc.isEmpty { break } }
                    return .solid(acc)
                case "hull":
                    let pts = solids.flatMap { $0.flatMap { [$0.0, $0.1, $0.2] } }
                    return .solid(SolidPrimitives.hull(pts).map { MeshTools.triangles(MeshTools.mesh(of: $0)) } ?? [])
                case "minkowski":
                    var acc = solids[0]
                    for s in solids.dropFirst() {
                        guard let a = SolidPrimitives.solid(acc), let b = SolidPrimitives.solid(s), let m = MeshOps.minkowski(a, b) else { continue }
                        acc = MeshTools.triangles(MeshTools.mesh(of: m))
                    }
                    return .solid(acc)
                default: return .solid(Geo.unionAll(solids))
                }
            }
            guard !shapes.isEmpty else { return .empty }
            switch op {
            case "difference": return .shape(shapes.dropFirst().reduce(shapes[0]) { PolygonBoolean.apply(.subtract, $0, $1) })
            case "intersection": return .shape(shapes.dropFirst().reduce(shapes[0]) { PolygonBoolean.apply(.intersect, $0, $1) })
            case "hull": return .shape([Prims.hull2D(shapes.joined().flatMap { $0 })])
            case "minkowski":
                var acc = shapes[0].joined().map { $0 }
                for s in shapes.dropFirst() { let b = s.joined(); acc = acc.flatMap { p in b.map { p + $0 } } }
                return .shape([Prims.hull2D(acc)])
            default: return .shape(shapes.dropFirst().reduce(shapes[0]) { PolygonBoolean.apply(.union, $0, $1) })
            }
        }
    }

    // MARK: Matrices

    struct Mat {
        var m: [[Double]]   // 3 × 4
        init(rows: [[Double]]) { m = rows }
        static let identity = Mat(rows: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]])
        static func translation(_ v: Vec3) -> Mat { Mat(rows: [[1, 0, 0, v.x], [0, 1, 0, v.y], [0, 0, 1, v.z]]) }
        static func scale(_ v: Vec3) -> Mat { Mat(rows: [[v.x, 0, 0, 0], [0, v.y, 0, 0], [0, 0, v.z, 0]]) }
        static func rotX(_ a: Double) -> Mat { let c = cos(a * .pi / 180), s = sin(a * .pi / 180); return Mat(rows: [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0]]) }
        static func rotY(_ a: Double) -> Mat { let c = cos(a * .pi / 180), s = sin(a * .pi / 180); return Mat(rows: [[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0]]) }
        static func rotZ(_ a: Double) -> Mat { let c = cos(a * .pi / 180), s = sin(a * .pi / 180); return Mat(rows: [[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0]]) }
        static func axisAngle(_ v: Vec3, _ a: Double) -> Mat {
            let n = v.normalized, c = cos(a * .pi / 180), s = sin(a * .pi / 180), t = 1 - c
            return Mat(rows: [[t * n.x * n.x + c, t * n.x * n.y - s * n.z, t * n.x * n.z + s * n.y, 0],
                              [t * n.x * n.y + s * n.z, t * n.y * n.y + c, t * n.y * n.z - s * n.x, 0],
                              [t * n.x * n.z - s * n.y, t * n.y * n.z + s * n.x, t * n.z * n.z + c, 0]])
        }
        static func mirror(_ v: Vec3) -> Mat {
            let n = v.normalized
            guard n.length > 0.5 else { return identity }
            return Mat(rows: [[1 - 2 * n.x * n.x, -2 * n.x * n.y, -2 * n.x * n.z, 0], [-2 * n.x * n.y, 1 - 2 * n.y * n.y, -2 * n.y * n.z, 0], [-2 * n.x * n.z, -2 * n.y * n.z, 1 - 2 * n.z * n.z, 0]])
        }
        static func * (a: Mat, b: Mat) -> Mat {
            var r = [[Double]](repeating: [0, 0, 0, 0], count: 3)
            for i in 0..<3 { for j in 0..<4 {
                r[i][j] = a.m[i][0] * b.m[0][j] + a.m[i][1] * b.m[1][j] + a.m[i][2] * b.m[2][j] + (j == 3 ? a.m[i][3] : 0)
            } }
            return Mat(rows: r)
        }
        func apply(_ p: Vec3) -> Vec3 {
            Vec3(m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z + m[0][3], m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z + m[1][3], m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z + m[2][3])
        }
        var det: Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
    }

    // MARK: Primitives

    enum Prims {
        static func box(_ o: Vec3, _ s: Vec3) -> [Tri3] {
            let x0 = o.x, y0 = o.y, z0 = o.z, x1 = o.x + s.x, y1 = o.y + s.y, z1 = o.z + s.z
            let bottom = [Vec3(x0, y0, z0), Vec3(x1, y0, z0), Vec3(x1, y1, z0), Vec3(x0, y1, z0)]
            let top = bottom.map { Vec3($0.x, $0.y, z1) }
            return ring(bottom, top) + cap(bottom, down: true) + cap(top, down: false)
        }
        /// Side band between two CCW (seen from above) rings, facing outward.
        static func ring(_ a: [Vec3], _ b: [Vec3]) -> [Tri3] {
            var out: [Tri3] = []
            let n = a.count
            for i in 0..<n {
                let j = (i + 1) % n
                out.append((a[i], a[j], b[j])); out.append((a[i], b[j], b[i]))
            }
            return out.filter { ($0.1 - $0.0).cross($0.2 - $0.0).length > 1e-18 }
        }
        static func cap(_ r: [Vec3], down: Bool) -> [Tri3] {
            guard r.count >= 3 else { return [] }
            return SolidPrimitives.polygon(r, normal: down ? Vec3(0, 0, -1) : Vec3.unitZ)
        }
        static func circle(_ r: Double, _ n: Int, z: Double) -> [Vec3] {
            (0..<n).map { i in let a = 2 * .pi * Double(i) / Double(n); return Vec3(r * cos(a), r * sin(a), z) }
        }
        /// OpenSCAD sphere: (n + 1) / 2 rings at polar angles 180 (i + 0.5) / rings.
        static func sphere(_ r: Double, _ n: Int) -> [Tri3] {
            let rings = (n + 1) / 2
            let rs: [[Vec3]] = (0..<rings).map { i in
                let phi = Double.pi * (Double(i) + 0.5) / Double(rings)
                return circle(r * sin(phi), n, z: r * cos(phi))
            }
            var out: [Tri3] = cap(rs[0], down: false) + cap(rs[rings - 1], down: true)
            for i in 0..<(rings - 1) { out += ring(rs[i + 1], rs[i]) }
            return out
        }
        static func cylinder(h: Double, r1: Double, r2: Double, center: Bool, n: Int) -> [Tri3] {
            let z0 = center ? -h / 2 : 0, z1 = z0 + h
            if r2 <= 1e-12 { let b = circle(r1, n, z: z0), apex = Vec3(0, 0, z1); return cap(b, down: true) + (0..<n).map { (b[$0], b[($0 + 1) % n], apex) } }
            if r1 <= 1e-12 { let t = circle(r2, n, z: z1), apex = Vec3(0, 0, z0); return cap(t, down: false) + (0..<n).map { (t[($0 + 1) % n], t[$0], apex) } }
            let b = circle(r1, n, z: z0), t = circle(r2, n, z: z1)
            return ring(b, t) + cap(b, down: true) + cap(t, down: false)
        }
        static func transform(_ g: Geo, _ m: Mat) -> Geo {
            let flip = m.det < 0
            switch g {
            case .solid(let t): return .solid(t.map { tr in let a = m.apply(tr.0), b = m.apply(tr.1), c = m.apply(tr.2); return flip ? (a, c, b) : (a, b, c) })
            case .shape(let l): return .shape(l.map { $0.map { let p = m.apply(Vec3($0.x, $0.y, 0)); return Vec2(p.x, p.y) } })
            case .empty: return .empty
            }
        }
        /// Outer loops (even-odd depth 0, 2…) and holes of a shape.
        static func split(_ loops: [[Vec2]]) -> (outer: [[Vec2]], holes: [[Vec2]]) {
            let n = PolygonBoolean.normalize(loops)
            return (n.filter { GeometryOps.signedArea($0) > 0 }, n.filter { GeometryOps.signedArea($0) < 0 })
        }
        static func linearExtrude(_ loops: [[Vec2]], h: Double, center: Bool, twist: Double, scale: Double, slices: Int) -> [Tri3] {
            guard h > 0 else { return [] }
            let z0 = center ? -h / 2 : 0
            let (outer, holes) = split(loops)
            func prism(_ p: [Vec2]) -> [Tri3] {
                // Twist is clockwise for positive angles in OpenSCAD.
                let n = twist != 0 ? max(slices, Int(abs(twist) / 5) + 1) : max(slices, 1)
                guard let s = SolidPrimitives.linearExtrude(p, z: z0, height: h, twist: -twist * .pi / 180, scale: scale, slices: n) else { return [] }
                return MeshTools.triangles(MeshTools.mesh(of: s))
            }
            var acc = Geo.unionAll(outer.map(prism))
            for hl in holes { acc = CSG.apply(.subtract, acc, prism(hl.reversed())) }
            return acc
        }
        static func rotateExtrude(_ loops: [[Vec2]], angle: Double, n: Int) -> [Tri3] {
            let (outer, holes) = split(loops)
            let full = abs(angle) >= 360 - 1e-9
            let steps = max(3, Int((Double(n) * abs(angle) / 360).rounded(.up)))
            func revolve(_ p0: [Vec2]) -> [Tri3] {
                let p = p0.map { Vec2(max($0.x, 0), $0.y) }
                guard p.count >= 3 else { return [] }
                func pt(_ q: Vec2, _ k: Int) -> Vec3 { let a = angle * .pi / 180 * Double(k) / Double(steps); return Vec3(q.x * cos(a), q.x * sin(a), q.y) }
                var out: [Tri3] = []
                let ccw = GeometryOps.signedArea(p) > 0
                for k in 0..<(full ? steps : steps) {
                    let k1 = full && k == steps - 1 ? 0 : k + 1
                    for i in 0..<p.count {
                        let a = p[i], b = p[(i + 1) % p.count]
                        let q = [pt(a, k), pt(b, k), pt(b, k1), pt(a, k1)]
                        let t1 = (q[0], q[1], q[2]), t2 = (q[0], q[2], q[3])
                        out += ccw ? [(t1.0, t1.2, t1.1), (t2.0, t2.2, t2.1)] : [t1, t2]
                    }
                }
                if !full {
                    out += SolidPrimitives.polygon(p.map { pt($0, 0) }, normal: Vec3(0, -1, 0) * (angle >= 0 ? 1 : -1))
                    let e = p.map { pt($0, steps) }
                    let a = angle * .pi / 180
                    out += SolidPrimitives.polygon(e, normal: Vec3(-sin(a), cos(a), 0) * (angle >= 0 ? 1 : -1))
                }
                let f = out.filter { ($0.1 - $0.0).cross($0.2 - $0.0).length > 1e-18 }
                return SolidPrimitives.signedVolume(f) < 0 ? f.map { ($0.0, $0.2, $0.1) } : f
            }
            var acc = Geo.unionAll(outer.map(revolve))
            for hl in holes { acc = CSG.apply(.subtract, acc, revolve(hl.reversed())) }
            return acc
        }
        static func offset(_ loops: [[Vec2]], _ d: Double, round: Bool, n: Int) -> [[Vec2]] {
            guard abs(d) > 1e-12 else { return loops }
            let norm = PolygonBoolean.normalize(loops)
            return norm.map { l in
                // Holes (clockwise) grow when the shape shrinks: offset every loop outward from the material.
                let isHole = GeometryOps.signedArea(l) < 0
                let base = isHole ? RG.offsetPolygon(l, -d).reversed() : RG.offsetPolygon(l, d)
                return Array(base)
            }.filter { $0.count >= 3 }
        }
        static func projection(_ tris: [Tri3], cut: Bool) -> [[Vec2]] {
            guard !tris.isEmpty else { return [] }
            if cut {
                var segs: [(Vec2, Vec2)] = []
                for t in tris {
                    let p = [t.0, t.1, t.2]
                    var pts: [Vec2] = []
                    for k in 0..<3 { let a = p[k], b = p[(k + 1) % 3]; if (a.z < 0) != (b.z < 0) { let u = a.z / (a.z - b.z); pts.append((a + (b - a) * u).xy) } }
                    if pts.count == 2 { segs.append((pts[0], pts[1])) }
                }
                return MeshOps.chain(segs).filter { $0.count >= 3 }
            }
            // Silhouette: union of the upward-facing triangles' footprints.
            var acc: [[Vec2]] = []
            for t in tris {
                let n = (t.1 - t.0).cross(t.2 - t.0)
                guard n.z > 1e-12 else { continue }
                let tri = [t.0.xy, t.1.xy, t.2.xy]
                acc = acc.isEmpty ? [tri] : PolygonBoolean.apply(.union, acc, [tri])
            }
            return acc
        }
        static func hull2D(_ pts0: [Vec2]) -> [Vec2] {
            let pts = pts0.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
            guard pts.count >= 3 else { return pts }
            var lower: [Vec2] = [], upper: [Vec2] = []
            for p in pts { while lower.count >= 2 && (lower[lower.count - 1] - lower[lower.count - 2]).cross(p - lower[lower.count - 2]) <= 0 { lower.removeLast() }; lower.append(p) }
            for p in pts.reversed() { while upper.count >= 2 && (upper[upper.count - 1] - upper[upper.count - 2]).cross(p - upper[upper.count - 2]) <= 0 { upper.removeLast() }; upper.append(p) }
            return Array(lower.dropLast() + upper.dropLast())
        }
    }
}

extension BBox3 {
    func intersects3(_ b: BBox3) -> Bool {
        !(isEmpty || b.isEmpty || b.min.x > max.x || b.max.x < min.x || b.min.y > max.y || b.max.y < min.y || b.min.z > max.z || b.max.z < min.z)
    }
}
