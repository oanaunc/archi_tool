// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Property lookup and criteria matching for QSELECT, FILTER, SELECTSIMILAR and fields.
public enum ObjectQuery {
    /// Type synonyms (AutoCAD names → Archi geometry type names).
    static let typeSynonyms: [String: String] = [
        "lwpolyline": "polyline", "pline": "polyline", "2dpolyline": "polyline", "mtext": "text", "dtext": "text", "attdef": "text",
        "block": "insert", "blockreference": "insert", "blockref": "insert", "dim": "dimension", "mleader": "leader", "multileader": "leader",
        "xline": "line", "ray": "line", "raster": "image", "3dsolid": "solid",
    ]
    static let categories: [String: Set<String>] = [
        "annotation": ["text", "dimension", "leader", "table"],
        "curve": ["line", "arc", "circle", "ellipse", "polyline", "spline"],
        "curves": ["line", "arc", "circle", "ellipse", "polyline", "spline"],
    ]

    /// Whether the object's type matches a type name, synonym, category ("annotation", "curve", "element") or "*".
    /// IFC entity names → Archi element / entity type names.
    static let ifcTypes: [String: String] = [
        "ifcwall": "wall", "ifcwallstandardcase": "wall", "ifcslab": "slab", "ifccolumn": "column", "ifcbeam": "beam",
        "ifcdoor": "door", "ifcwindow": "window", "ifcopeningelement": "opening", "ifcroof": "roof", "ifcstair": "stair",
        "ifcstairflight": "stair", "ifcrailing": "railing", "ifcspace": "space", "ifccurtainwall": "curtainwall",
        "ifcfurnishingelement": "component", "ifcfurniture": "component", "ifcbuildingelementproxy": "component",
        "ifcgrid": "gridline", "ifcgridaxis": "gridline", "ifcannotation": "annotation",
    ]

    public static func typeMatches(_ id: EntityID, _ type: String, doc: ArchiDocument) -> Bool {
        var t = type.lowercased()
        if let m = ifcTypes[t] { t = m }
        if t == "*" || t == "all" || t == "any" { return true }
        if let e = doc.entity(id) {
            let tn = e.typeName
            if let c = categories[t] { return c.contains(tn) }
            if wildcard(tn, t) { return true }
            return (typeSynonyms[t] ?? t) == tn || (t.hasSuffix("s") && String(t.dropLast()) == tn)
        }
        if let el = doc.element(id) {
            if ["element", "elements", "bim", "building"].contains(t) { return true }
            let tn = el.typeName.lowercased()
            if case .opening(let o) = el.geometry, "\(o.kind)".lowercased() == t || "\(o.kind)s".lowercased() == t { return true }
            return tn == t || (t.hasSuffix("s") && String(t.dropLast()) == tn) || wildcard(tn, t)
        }
        return false
    }

    /// Type name used for display / similarity.
    public static func typeName(_ id: EntityID, doc: ArchiDocument) -> String? { doc.entity(id)?.typeName ?? doc.element(id)?.typeName }

    /// Property value as text. Understands the Properties-panel names plus common AutoCAD names
    /// (length, area, x, y, name, contents, height…) and custom props ("prop.key" or the bare key).
    public static func value(_ id: EntityID, _ name: String, doc: ArchiDocument) -> String? {
        let n = name.lowercased()
        if let e = doc.entity(id) {
            switch n {
            case "type", "objecttype": return e.typeName
            case "length":
                switch e.geometry {
                case .line, .arc, .circle, .ellipse, .polyline, .spline: return fmt(GeometryOps.length(e.geometry, doc: doc), 6)
                default: return nil
                }
            case "perimeter", "circumference":
                switch e.geometry {
                case .circle(let c): return fmt(2 * .pi * c.radius, 6)
                case .polyline, .ellipse, .spline, .hatch: return fmt(GeometryOps.length(e.geometry, doc: doc), 6)
                default: return nil
                }
            case "area": return GeometryOps.area(e.geometry, doc: doc).map { fmt(abs($0), 6) }
            case "name", "blockname", "effectivename": if case .insert(let i) = e.geometry { return i.block }; return nil
            case "contents", "text", "textstring", "value":
                switch e.geometry {
                case .text(let t): return t.content
                case .leader(let l): return l.text
                case .dimension(let d): return d.textOverride ?? fmt(CommandHelpers.dimMeasurement(d), doc.dimStyle(d.style).decimals)
                default: break
                }
            case "height":
                switch e.geometry {
                case .text(let t): return fmt(t.height, 6)
                case .leader(let l): return fmt(l.textHeight, 6)
                case .table(let t): return fmt(t.textHeight, 6)
                default: break
                }
            case "x", "y":
                let pts: Vec2?
                switch e.geometry {
                case .point(let p): pts = p
                case .line(let l): pts = l.a
                case .circle(let c): pts = c.center
                case .arc(let a): pts = a.center
                case .ellipse(let el): pts = el.center
                case .text(let t): pts = t.position
                case .insert(let i): pts = i.position
                case .polyline(let p): pts = p.vertices.first?.p
                case .image(let im): pts = im.origin
                case .table(let t): pts = t.origin
                default: pts = nil
                }
                if let p = pts { return fmt(n == "x" ? p.x : p.y, 6) }
            case "color": return e.color.text
            default: break
            }
            if n.hasPrefix("prop.") { return e.props[String(name.dropFirst(5))] }
            if let v = PropertyAccess.getProperty(e, name) { return v }
            if let k = e.props.keys.first(where: { $0.lowercased() == n }) { return e.props[k] }
            if case .insert(let ins) = e.geometry, let k = ins.attributes.keys.first(where: { $0.lowercased() == n }) { return ins.attributes[k] }
            return nil
        }
        if let el = doc.element(id) {
            switch n {
            case "type", "objecttype": return el.typeName
            case "area":
                let f = CommandHelpers.footprint(el, doc: doc)
                return f.count >= 3 ? fmt(abs(GeometryOps.signedArea(f)), 6) : nil
            default: break
            }
            if n.hasPrefix("prop.") { return el.props[String(name.dropFirst(5))] }
            if let v = PropertyAccess.getProperty(el, name) { return v }
            if let k = el.props.keys.first(where: { $0.lowercased() == n }) { return el.props[k] }
            if n == "material" {
                // Elements without their own material report their wall type's plies ("Brick+Insulation").
                if let m = el.material, !m.isEmpty { return m }
                if case .wall(let w) = el.geometry, let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }) {
                    return wt.plies.map(\.material).joined(separator: "+")
                }
            }
        }
        return nil
    }

    // MARK: Criteria

    public enum Op: String, CaseIterable { case eq = "=", ne = "!=", gt = ">", lt = "<", ge = ">=", le = "<=" }

    public struct Criterion: Equatable {
        public var property: String
        public var op: Op
        public var value: String
        public init(_ property: String, _ op: Op, _ value: String) { self.property = property; self.op = op; self.value = value }

        /// Parses "radius>50", "layer=A-*", "type = circle", "color<>1".
        public init?(parse s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            let ops: [(String, Op)] = [(">=", .ge), ("<=", .le), ("!=", .ne), ("<>", .ne), ("==", .eq), ("=", .eq), (">", .gt), ("<", .lt)]
            for (sym, op) in ops {
                if let r = t.range(of: sym) {
                    let p = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                    let v = t[r.upperBound...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    guard !p.isEmpty else { return nil }
                    self.init(p, op, v); return
                }
            }
            // A bare word is a type ("IfcWall", "circle", "doors").
            let word = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !word.isEmpty, word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "*" || $0 == "?" || $0 == "-" }) {
                self.init("type", .eq, word); return
            }
            return nil
        }
        public static func op(_ s: String) -> Op? {
            switch s.lowercased() {
            case "=", "==", "equals", "eq": return .eq
            case "!=", "<>", "ne", "notequal": return .ne
            case ">", "gt", "greater": return .gt
            case "<", "lt", "less": return .lt
            case ">=", "ge": return .ge
            case "<=", "le": return .le
            default: return nil
            }
        }

        public func matches(_ id: EntityID, doc: ArchiDocument) -> Bool {
            if property.lowercased() == "type" || property.lowercased() == "objecttype" {
                let m = ObjectQuery.typeMatches(id, value, doc: doc)
                return op == .ne ? !m : (op == .eq ? m : false)
            }
            guard let actual = ObjectQuery.value(id, property, doc: doc) else { return op == .ne }
            return ObjectQuery.compare(actual, op, value, property: property)
        }
    }

    /// Numeric comparison when both sides are numbers (tolerance 1e-9 relative), otherwise case-insensitive text with * and ? wildcards.
    public static func compare(_ actual: String, _ op: Op, _ expected: String, property: String = "") -> Bool {
        if property.lowercased() == "color", let a = ColorRef.parse(actual), let b = ColorRef.parse(expected) {
            switch op { case .eq: return a == b; case .ne: return a != b; default: break }
        }
        if let a = Double(actual) ?? InputParser.parseNumber(actual), let b = Double(expected) ?? InputParser.parseNumber(expected) {
            let tol = 1e-9 * max(1, abs(a), abs(b))
            switch op {
            case .eq: return abs(a - b) <= tol
            case .ne: return abs(a - b) > tol
            case .gt: return a > b + tol
            case .lt: return a < b - tol
            case .ge: return a >= b - tol
            case .le: return a <= b + tol
            }
        }
        let a = actual.lowercased(), b = expected.lowercased()
        switch op {
        case .eq: return wildcard(a, b)
        case .ne: return !wildcard(a, b)
        case .gt: return a > b
        case .lt: return a < b
        case .ge: return a >= b
        case .le: return a <= b
        }
    }

    /// Wildcard match (* any run, ? one character, # a digit).
    public static func wildcard(_ s: String, _ pattern: String) -> Bool {
        let str = Array(s), pat = Array(pattern)
        var memo = [Int: Bool]()
        func m(_ i: Int, _ j: Int) -> Bool {
            let key = i * (pat.count + 1) + j
            if let v = memo[key] { return v }
            var r: Bool
            if j == pat.count { r = i == str.count }
            else if pat[j] == "*" { r = m(i, j + 1) || (i < str.count && m(i + 1, j)) }
            else if i < str.count && (pat[j] == "?" || pat[j] == str[i] || (pat[j] == "#" && str[i].isNumber)) { r = m(i + 1, j + 1) }
            else { r = false }
            memo[key] = r
            return r
        }
        return m(0, 0)
    }

    /// A filter expression: criteria joined by "," "&" or " and " (all must hold), groups joined by "|" or " or ".
    public struct Filter {
        public var groups: [[Criterion]]
        public init(groups: [[Criterion]]) { self.groups = groups }
        public init?(parse s: String) {
            let normalized = s.replacingOccurrences(of: " or ", with: "|", options: .caseInsensitive)
                .replacingOccurrences(of: " and ", with: "&", options: .caseInsensitive)
            var gs: [[Criterion]] = []
            for g in normalized.split(separator: "|") {
                var cs: [Criterion] = []
                for c in g.split(whereSeparator: { $0 == "&" || $0 == "," || $0 == ";" }) {
                    guard let cr = Criterion(parse: String(c)) else { return nil }
                    cs.append(cr)
                }
                if !cs.isEmpty { gs.append(cs) }
            }
            guard !gs.isEmpty else { return nil }
            groups = gs
        }
        public func matches(_ id: EntityID, doc: ArchiDocument) -> Bool {
            groups.contains { $0.allSatisfy { $0.matches(id, doc: doc) } }
        }
    }

    // MARK: Similarity (SELECTSIMILAR, SELECTSIMILARMODE bits)

    public struct SimilarMode: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let color = SimilarMode(rawValue: 1), layer = SimilarMode(rawValue: 2), linetype = SimilarMode(rawValue: 4)
        public static let ltscale = SimilarMode(rawValue: 8), lineweight = SimilarMode(rawValue: 16), plotStyle = SimilarMode(rawValue: 32)
        public static let style = SimilarMode(rawValue: 64), name = SimilarMode(rawValue: 128)
        public static let `default`: SimilarMode = [.layer, .name]
    }

    /// Whether `b` is similar to `a`: same type always, plus the properties selected by the mode.
    public static func similar(_ a: EntityID, _ b: EntityID, mode: SimilarMode, doc: ArchiDocument) -> Bool {
        if let x = doc.entity(a), let y = doc.entity(b) {
            guard x.typeName == y.typeName else { return false }
            if mode.contains(.color) && x.color != y.color { return false }
            if mode.contains(.layer) && x.layer.caseInsensitiveCompare(y.layer) != .orderedSame { return false }
            if mode.contains(.linetype) && (x.linetype ?? "ByLayer").lowercased() != (y.linetype ?? "ByLayer").lowercased() { return false }
            if mode.contains(.ltscale) && (x.props["ltscale"] ?? "1") != (y.props["ltscale"] ?? "1") { return false }
            if mode.contains(.lineweight) && x.lineweight != y.lineweight { return false }
            if mode.contains(.style) && styleName(x) != styleName(y) { return false }
            if mode.contains(.name) && objectName(x) != objectName(y) { return false }
            return true
        }
        if let x = doc.element(a), let y = doc.element(b) {
            guard x.typeName == y.typeName else { return false }
            if mode.contains(.layer) && x.layer != y.layer { return false }
            if mode.contains(.name) && x.name != y.name { return false }
            if mode.contains(.style) && x.material != y.material { return false }
            return true
        }
        return false
    }
    static func styleName(_ e: Entity) -> String? {
        switch e.geometry {
        case .text(let t): return t.style
        case .dimension(let d): return d.style
        case .hatch(let h): return h.pattern
        default: return nil
        }
    }
    static func objectName(_ e: Entity) -> String? {
        switch e.geometry {
        case .insert(let i): return i.block
        case .image(let im): return im.path
        default: return nil
        }
    }
}
