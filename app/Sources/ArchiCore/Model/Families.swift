// Oanarina Archi Tool — GPL-3.0-or-later
// Document-defined parametric families (family editor data model): parameters with formulas, 2D profiles,
// solid/void forms (box, cylinder, extrusion, sweep, revolve), parametric arrays, conditional visibility and nested
// families. Instances (components, or doors/windows with props["family"]) regenerate from the definition.
import Foundation

public enum FamilyParameterKind: String, Codable, CaseIterable {
    case length, angle, number, integer, text, yesNo, material, area, volume
    public var isNumeric: Bool { self != .text && self != .material }
}

public struct FamilyParameter: Codable, Hashable {
    public var name: String
    public var kind: FamilyParameterKind
    /// Default value (numbers as text; yes/no as 1/0).
    public var value: String
    /// Expression over other parameters (driving the value); nil = free.
    public var formula: String?
    /// Instance parameter (each placement may override) or type parameter.
    public var instance: Bool
    /// Validation range (PAR-031): values are clamped into [min, max].
    public var min: Double?
    public var max: Double?
    public init(_ name: String, _ kind: FamilyParameterKind = .length, value: String, formula: String? = nil, instance: Bool = true, min: Double? = nil, max: Double? = nil) {
        self.name = name; self.kind = kind; self.value = value; self.formula = formula; self.instance = instance; self.min = min; self.max = max
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(String.self, forKey: .name), try c.decodeIfPresent(FamilyParameterKind.self, forKey: .kind) ?? .length,
                  value: try c.decodeIfPresent(String.self, forKey: .value) ?? "0", formula: try c.decodeIfPresent(String.self, forKey: .formula),
                  instance: try c.decodeIfPresent(Bool.self, forKey: .instance) ?? true,
                  min: try c.decodeIfPresent(Double.self, forKey: .min), max: try c.decodeIfPresent(Double.self, forKey: .max))
    }
}

/// A 2D profile whose vertices are expressions (x, y) over the family parameters (profile families, PAR-013),
/// or a reference to a built-in library profile scaled to `width` × `height` expressions.
public struct FamilyProfile: Codable, Hashable {
    public var name: String
    public var points: [[String]]
    /// Built-in profile name (ProfileLibrary) used when `points` is empty.
    public var library: String?
    public var width: String?
    public var height: String?
    public init(name: String, points: [[String]] = [], library: String? = nil, width: String? = nil, height: String? = nil) {
        self.name = name; self.points = points; self.library = library; self.width = width; self.height = height
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), points: try c.decodeIfPresent([[String]].self, forKey: .points) ?? [],
                  library: try c.decodeIfPresent(String.self, forKey: .library), width: try c.decodeIfPresent(String.self, forKey: .width),
                  height: try c.decodeIfPresent(String.self, forKey: .height))
    }
}

public enum FamilyFormKind: String, Codable, CaseIterable { case box, cylinder, extrusion, sweep, revolve, nested }

/// One solid (or void) form of a family. Numeric fields are expressions over the parameters.
public struct FamilyForm: Codable, Hashable {
    public var kind: FamilyFormKind
    public var name: String
    /// Placement of the form's local origin (family coordinates: X width, Y depth, Z up) and rotation about Z (degrees).
    public var x: String, y: String, z: String, rotation: String
    /// box: width/depth/height; cylinder: radius/height; extrusion: height; revolve: angle (degrees, about the local Z axis
    /// with the profile in the XZ plane); nested: bindings of the nested family's parameters.
    public var dims: [String: String]
    /// Profile name (a FamilyProfile of this family or a ProfileLibrary name) for extrusion, sweep and revolve.
    public var profile: String?
    /// Sweep path vertices (x, y, z expressions).
    public var path: [[String]]
    /// Material name, or "=Param" to use a material parameter.
    public var material: String?
    /// Conditional visibility: the form is built only when this expression is non-zero (PAR-035).
    public var visible: String?
    /// Void forms cut the solid forms of the family (PAR-005).
    public var void: Bool
    /// Parametric array (PAR-036): number of copies and the offset between them.
    public var arrayCount: String?
    public var arrayDX: String?, arrayDY: String?, arrayDZ: String?
    /// Nested family name (kind .nested).
    public var family: String?
    public init(_ kind: FamilyFormKind, name: String = "", x: String = "0", y: String = "0", z: String = "0", rotation: String = "0",
                dims: [String: String] = [:], profile: String? = nil, path: [[String]] = [], material: String? = nil, visible: String? = nil,
                void: Bool = false, arrayCount: String? = nil, arrayDX: String? = nil, arrayDY: String? = nil, arrayDZ: String? = nil, family: String? = nil) {
        self.kind = kind; self.name = name; self.x = x; self.y = y; self.z = z; self.rotation = rotation; self.dims = dims
        self.profile = profile; self.path = path; self.material = material; self.visible = visible; self.void = void
        self.arrayCount = arrayCount; self.arrayDX = arrayDX; self.arrayDY = arrayDY; self.arrayDZ = arrayDZ; self.family = family
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decodeIfPresent(FamilyFormKind.self, forKey: .kind) ?? .box, name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  x: try c.decodeIfPresent(String.self, forKey: .x) ?? "0", y: try c.decodeIfPresent(String.self, forKey: .y) ?? "0",
                  z: try c.decodeIfPresent(String.self, forKey: .z) ?? "0", rotation: try c.decodeIfPresent(String.self, forKey: .rotation) ?? "0",
                  dims: try c.decodeIfPresent([String: String].self, forKey: .dims) ?? [:], profile: try c.decodeIfPresent(String.self, forKey: .profile),
                  path: try c.decodeIfPresent([[String]].self, forKey: .path) ?? [], material: try c.decodeIfPresent(String.self, forKey: .material),
                  visible: try c.decodeIfPresent(String.self, forKey: .visible), void: try c.decodeIfPresent(Bool.self, forKey: .void) ?? false,
                  arrayCount: try c.decodeIfPresent(String.self, forKey: .arrayCount), arrayDX: try c.decodeIfPresent(String.self, forKey: .arrayDX),
                  arrayDY: try c.decodeIfPresent(String.self, forKey: .arrayDY), arrayDZ: try c.decodeIfPresent(String.self, forKey: .arrayDZ),
                  family: try c.decodeIfPresent(String.self, forKey: .family))
    }
}

/// A loadable family defined in the document (Revit .rfa / ArchiCAD GDL object equivalent).
public struct FamilyDefinition: Codable, Hashable {
    public var name: String
    /// "Generic Model", "Furniture", "Door", "Window", "Profile", "Casework", "Lighting"…
    public var category: String
    public var parameters: [FamilyParameter]
    public var profiles: [FamilyProfile]
    public var forms: [FamilyForm]
    /// Family types: type name → parameter values (the family types table).
    public var types: [String: [String: String]]
    public var description: String
    public init(name: String, category: String = "Generic Model", parameters: [FamilyParameter] = [], profiles: [FamilyProfile] = [],
                forms: [FamilyForm] = [], types: [String: [String: String]] = [:], description: String = "") {
        self.name = name; self.category = category; self.parameters = parameters; self.profiles = profiles; self.forms = forms
        self.types = types; self.description = description
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), category: try c.decodeIfPresent(String.self, forKey: .category) ?? "Generic Model",
                  parameters: try c.decodeIfPresent([FamilyParameter].self, forKey: .parameters) ?? [],
                  profiles: try c.decodeIfPresent([FamilyProfile].self, forKey: .profiles) ?? [],
                  forms: try c.decodeIfPresent([FamilyForm].self, forKey: .forms) ?? [],
                  types: try c.decodeIfPresent([String: [String: String]].self, forKey: .types) ?? [:],
                  description: try c.decodeIfPresent(String.self, forKey: .description) ?? "")
    }
    public func parameter(_ n: String) -> FamilyParameter? { parameters.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public func profile(_ n: String) -> FamilyProfile? { profiles.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
}

extension ArchiDocument {
    public func family(named n: String?) -> FamilyDefinition? {
        guard let n = n else { return nil }
        return families.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    public func familyIndex(_ n: String) -> Int? { families.firstIndex { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
}

// MARK: - Expressions

/// Expression evaluator for family formulas: + − × ÷ ^, parentheses, comparisons (< <= > >= == !=), and/or (&& ||, and/or),
/// not, if(c, a, b), min/max, abs, sqrt, round/floor/ceil, sin/cos/tan (degrees), pi. Identifiers may contain letters,
/// digits, underscores and dots; lookups are case-insensitive.
public enum FamilyExpr {
    public static func evaluate(_ s: String, _ vars: [String: Double]) -> Double? {
        var lower: [String: Double] = [:]
        for (k, v) in vars { lower[k.lowercased()] = v }
        var p = Parser(Array(s), lower)
        p.skip()
        guard let v = p.or(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    /// Identifiers used by an expression (lower-cased, functions excluded).
    public static func identifiers(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        let ch = Array(s)
        var i = 0
        func flush(_ next: Character?) {
            if let f = cur.first, f.isLetter || f == "_" {
                let l = cur.lowercased()
                if next != "(" && !["pi", "and", "or", "not", "true", "false"].contains(l) && !out.contains(l) { out.append(l) }
            }
            cur = ""
        }
        while i < ch.count {
            let c = ch[i]
            if c.isLetter || c.isNumber || c == "_" || (c == "." && !cur.isEmpty) { cur.append(c) }
            else { var j = i; while j < ch.count && ch[j] == " " { j += 1 }; flush(j < ch.count ? ch[j] : nil) }
            i += 1
        }
        flush(nil)
        return out
    }

    struct Parser {
        let c: [Character]; var i = 0; let vars: [String: Double]
        init(_ c: [Character], _ v: [String: Double]) { self.c = c; vars = v }
        var atEnd: Bool { i >= c.count }
        mutating func skip() { while i < c.count && c[i] == " " { i += 1 } }
        mutating func eat(_ s: String) -> Bool {
            let a = Array(s)
            guard i + a.count <= c.count, Array(c[i..<(i + a.count)]) == a else { return false }
            if a.last!.isLetter, i + a.count < c.count, c[i + a.count].isLetter || c[i + a.count].isNumber || c[i + a.count] == "_" { return false }
            i += a.count; skip(); return true
        }
        mutating func or() -> Double? {
            guard var v = and() else { return nil }
            while eat("||") || eat("or") { guard let r = and() else { return nil }; v = (v != 0 || r != 0) ? 1 : 0 }
            return v
        }
        mutating func and() -> Double? {
            guard var v = cmp() else { return nil }
            while eat("&&") || eat("and") { guard let r = cmp() else { return nil }; v = (v != 0 && r != 0) ? 1 : 0 }
            return v
        }
        mutating func cmp() -> Double? {
            guard let a = add() else { return nil }
            for op in ["<=", ">=", "==", "!=", "<>", "<", ">", "="] {
                if eat(op) {
                    guard let b = add() else { return nil }
                    switch op {
                    case "<=": return a <= b + 1e-9 ? 1 : 0
                    case ">=": return a >= b - 1e-9 ? 1 : 0
                    case "==", "=": return abs(a - b) <= 1e-9 * max(1, abs(a), abs(b)) ? 1 : 0
                    case "!=", "<>": return abs(a - b) > 1e-9 * max(1, abs(a), abs(b)) ? 1 : 0
                    case "<": return a < b ? 1 : 0
                    default: return a > b ? 1 : 0
                    }
                }
            }
            return a
        }
        mutating func add() -> Double? {
            guard var v = mul() else { return nil }
            while true {
                if eat("+") { guard let r = mul() else { return nil }; v += r }
                else if eat("-") { guard let r = mul() else { return nil }; v -= r }
                else { return v }
            }
        }
        mutating func mul() -> Double? {
            guard var v = pow_() else { return nil }
            while true {
                if eat("*") || eat("×") { guard let r = pow_() else { return nil }; v *= r }
                else if eat("/") || eat("÷") { guard let r = pow_() else { return nil }; v /= r }
                else if eat("%") { guard let r = pow_() else { return nil }; v = v.truncatingRemainder(dividingBy: r) }
                else { return v }
            }
        }
        mutating func pow_() -> Double? {
            guard let b = unary() else { return nil }
            if eat("^") { guard let e = pow_() else { return nil }; return Foundation.pow(b, e) }
            return b
        }
        mutating func unary() -> Double? {
            if eat("-") { return unary().map { -$0 } }
            if eat("+") { return unary() }
            if eat("!") || eat("not") { return unary().map { $0 == 0 ? 1 : 0 } }
            return atom()
        }
        mutating func args() -> [Double]? {
            var out: [Double] = []
            if eat(")") { return out }
            while true {
                guard let v = or() else { return nil }
                out.append(v)
                if eat(",") || eat(";") { continue }
                guard eat(")") else { return nil }
                return out
            }
        }
        mutating func atom() -> Double? {
            skip()
            guard i < c.count else { return nil }
            if eat("(") { let v = or(); guard eat(")") else { return nil }; return v }
            if c[i].isNumber || c[i] == "." {
                var s = ""
                while i < c.count, c[i].isNumber || c[i] == "." { s.append(c[i]); i += 1 }
                if i < c.count, c[i] == "e" || c[i] == "E", i + 1 < c.count, c[i + 1].isNumber || c[i + 1] == "-" || c[i + 1] == "+" {
                    s.append("e"); i += 1
                    if c[i] == "-" || c[i] == "+" { s.append(c[i]); i += 1 }
                    while i < c.count, c[i].isNumber { s.append(c[i]); i += 1 }
                }
                skip()
                return Double(s)
            }
            if c[i].isLetter || c[i] == "_" {
                var name = ""
                while i < c.count, c[i].isLetter || c[i].isNumber || c[i] == "_" || c[i] == "." { name.append(c[i]); i += 1 }
                skip()
                let l = name.lowercased()
                if eat("(") {
                    guard let a = args() else { return nil }
                    func d2r(_ x: Double) -> Double { x * .pi / 180 }
                    switch (l, a.count) {
                    case ("if", 3): return a[0] != 0 ? a[1] : a[2]
                    case ("min", _) where !a.isEmpty: return a.min()
                    case ("max", _) where !a.isEmpty: return a.max()
                    case ("abs", 1): return abs(a[0])
                    case ("sqrt", 1): return a[0].squareRoot()
                    case ("round", 1): return a[0].rounded()
                    case ("round", 2): return a[1] != 0 ? (a[0] / a[1]).rounded() * a[1] : a[0]
                    case ("floor", 1): return a[0].rounded(.down)
                    case ("ceil", 1): return a[0].rounded(.up)
                    case ("sin", 1): return sin(d2r(a[0]))
                    case ("cos", 1): return cos(d2r(a[0]))
                    case ("tan", 1): return tan(d2r(a[0]))
                    case ("asin", 1): return asin(a[0]) * 180 / .pi
                    case ("acos", 1): return acos(a[0]) * 180 / .pi
                    case ("atan", 1): return atan(a[0]) * 180 / .pi
                    case ("atan2", 2): return atan2(a[0], a[1]) * 180 / .pi
                    case ("exp", 1): return Foundation.exp(a[0])
                    case ("ln", 1): return Foundation.log(a[0])
                    case ("log", 1): return log10(a[0])
                    default: return nil
                    }
                }
                switch l {
                case "pi": return .pi
                case "true", "yes": return 1
                case "false", "no": return 0
                default: return vars[l]
                }
            }
            return nil
        }
    }

    /// Resolves parameter values: fixed values plus formulas in dependency order. Returns values (lower-cased names),
    /// text values and errors (unknown names, circular references, unparsable formulas).
    public static func resolve(_ def: FamilyDefinition, overrides: [String: String] = [:], type: String? = nil, extra: [String: Double] = [:])
        -> (values: [String: Double], text: [String: String], errors: [String]) {
        var raw: [String: String] = [:]
        for p in def.parameters { raw[p.name.lowercased()] = p.value }
        if let t = type, let tv = def.types.first(where: { $0.key.caseInsensitiveCompare(t) == .orderedSame })?.value {
            for (k, v) in tv { raw[k.lowercased()] = v }
        }
        for (k, v) in overrides { raw[k.lowercased()] = v }
        var vals: [String: Double] = [:], text: [String: String] = [:], errors: [String] = []
        for (k, v) in extra { vals[k.lowercased()] = v }
        var pending: [String: String] = [:]
        for p in def.parameters {
            let k = p.name.lowercased()
            // An override on an instance beats the formula only when the parameter has no formula.
            if let f = p.formula, !f.trimmingCharacters(in: .whitespaces).isEmpty { pending[k] = f; continue }
            let s = raw[k] ?? p.value
            if p.kind.isNumeric {
                if var d = Double(s.trimmingCharacters(in: .whitespaces)) ?? evaluate(s, vals) {
                    if let lo = p.min, d < lo { d = lo }
                    if let hi = p.max, d > hi { d = hi }
                    vals[k] = d
                } else { errors.append("\(p.name): \"\(s)\" is not a number"); vals[k] = 0 }
            } else { text[k] = s }
        }
        var progress = true
        while !pending.isEmpty && progress {
            progress = false
            for (k, f) in pending.sorted(by: { $0.key < $1.key }) {
                let ids = identifiers(f)
                if let bad = ids.first(where: { vals[$0] == nil && pending[$0] == nil }) {
                    errors.append("\(k): unknown parameter \"\(bad)\""); pending[k] = nil; vals[k] = 0; progress = true; continue
                }
                guard ids.allSatisfy({ vals[$0] != nil }) else { continue }
                if let v = evaluate(f, vals) { vals[k] = v } else { errors.append("\(k): cannot evaluate \"\(f)\""); vals[k] = 0 }
                pending[k] = nil; progress = true
            }
        }
        for k in pending.keys.sorted() { errors.append("\(k): circular reference"); vals[k] = 0 }
        // Validation ranges and integer rounding.
        for p in def.parameters {
            let k = p.name.lowercased()
            guard var v = vals[k] else { continue }
            if p.kind == .integer || p.kind == .yesNo { v = v.rounded() }
            if let lo = p.min, v < lo { v = lo }
            if let hi = p.max, v > hi { v = hi }
            vals[k] = v
        }
        return (vals, text, errors)
    }
}
