// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Keeps derived annotation content current after every edit: fields, annotative heights and table formulas.
public enum DocumentUpdaters {
    /// Returns true if the document changed.
    @discardableResult
    public static func run(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        if Constraints.updateAll(&doc) { changed = true }
        if BIMUpdaters.hasAssociative(doc), BIMUpdaters.run(&doc) { changed = true }
        if Fields.updateAll(&doc) { changed = true }
        if Annotative.updateAll(&doc) { changed = true }
        if TableFormulas.updateAll(&doc) { changed = true }
        if AssociativeMarks.updateAll(&doc) { changed = true }
        if AssociativeHatch.updateAll(&doc) { changed = true }
        if DimAssociation.updateAll(&doc) { changed = true }
        if DimOverrides.updateAll(&doc) { changed = true }
        if DimBreaks.updateAll(&doc) { changed = true }
        if AssocArray.updateAll(&doc) { changed = true }
        return changed
    }
}

// MARK: - Associative centre marks and centre lines

/// Centre marks (props centermarkOf/centermarkAxis) and centre lines (prop centerlineOf) follow their source objects.
public enum AssociativeMarks {
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices {
            let p = doc.entities[i].props
            guard p["centermarkOf"] != nil || p["centerlineOf"] != nil, case .line(let cur) = doc.entities[i].geometry else { continue }
            let ext = p["centerExt"].flatMap(Double.init) ?? 0
            var new: LineGeom? = nil
            if let src = p["centermarkOf"].flatMap(Int.init), let host = doc.entity(src) {
                let (c, r): (Vec2, Double)
                switch host.geometry { case .circle(let g): (c, r) = (g.center, g.radius); case .arc(let g): (c, r) = (g.center, g.radius); default: continue }
                let lines = DraftGeometry.centerMark(center: c, radius: r, extension: ext)
                new = p["centermarkAxis"] == "v" ? lines[1] : lines[0]
            } else if let ids = p["centerlineOf"]?.split(separator: ",").compactMap({ Int($0) }), ids.count == 2,
                      case .line(let a)? = doc.entity(ids[0])?.geometry, case .line(let b)? = doc.entity(ids[1])?.geometry {
                new = DraftGeometry.centerLine(a, b, extension: ext)
            }
            if let n = new, !(n.a.isClose(cur.a, tol: 1e-9) && n.b.isClose(cur.b, tol: 1e-9)) { doc.entities[i].geometry = .line(n); changed = true }
        }
        return changed
    }
}

// MARK: - Fields

/// Text fields: an entity prop "field" holds a template such as "Area: %<Area(12):m2:2>% m²".
/// Field codes: Area(id) Length(id) Perimeter(id) Radius(id) Prop(id,name) Var(name) Count(type) Date(format) FileName.
/// Optional format after ":": a unit (mm, cm, m, in, ft, mm2, cm2, m2, ft2) and/or number of decimals.
public enum Fields {
    public static let placeholder = "####"

    /// Evaluates one field code ("Area(12):m2:2"). Volatile fields (Date) only when `volatile` is true.
    public static func evaluate(_ code: String, doc: ArchiDocument, volatile: Bool = true, layout: Int? = nil) -> String? {
        // Formula fields: Expr(<arithmetic with {Field} references, field calls and numeric variables>)[:decimals]
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("expr("), let close = trimmed.lastIndex(of: ")") {
            let inner = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<close])
            let fmtPart = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            guard let v = expression(inner, doc: doc, volatile: volatile, layout: layout) else { return nil }
            if let d = Int(fmtPart) { return String(format: "%.\(max(0, min(d, 10)))f", v) }
            return fmt(v, 6)
        }
        var parts = code.split(separator: ":", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        let head = parts.removeFirst()
        var name = head, args: [String] = []
        if let o = head.firstIndex(of: "("), head.hasSuffix(")") {
            name = String(head[..<o])
            args = head[head.index(after: o)..<head.index(before: head.endIndex)].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var unit: String? = nil, decimals: Int? = nil
        for p in parts where !p.isEmpty { if let d = Int(p) { decimals = d } else { unit = p.lowercased() } }
        func id(_ i: Int) -> EntityID? { args.count > i ? Int(args[i].trimmingCharacters(in: CharacterSet(charactersIn: "#"))) : nil }
        func number(_ v: Double, dim: Int) -> String {
            var x = v
            if let u = unit {
                let base = u.replacingOccurrences(of: "2", with: "").replacingOccurrences(of: "²", with: "")
                if let f = InputParser.unitSuffixes.first(where: { $0.0 == base })?.1 {
                    let perUnit = doc.units.mm / f
                    x = v * pow(perUnit, Double(dim))
                }
            }
            if let d = decimals { return String(format: "%.\(max(0, min(d, 10)))f", x) }
            return fmt(x, dim == 2 ? 2 : 0)
        }
        switch name.lowercased() {
        case "area":
            guard let i = id(0), let v = ObjectQuery.value(i, "area", doc: doc).flatMap(Double.init) else { return nil }
            return number(v, dim: 2)
        case "length", "perimeter", "radius", "diameter", "height", "measurement":
            guard let i = id(0), let v = ObjectQuery.value(i, name.lowercased(), doc: doc).flatMap(Double.init) else { return nil }
            return number(v, dim: 1)
        case "prop", "objprop":
            guard let i = id(0), args.count >= 2, let v = ObjectQuery.value(i, args[1], doc: doc) else { return nil }
            if let d = Double(v), unit != nil || decimals != nil { return number(d, dim: 1) }
            return v
        case "var", "sysvar":
            guard let n = args.first else { return nil }
            switch n.uppercased() {
            case "CLAYER": return doc.currentLayer
            case "DIMSTYLE": return doc.currentDimStyle
            case "PROJECTNAME": return doc.info.name
            case "PROJECTNUMBER": return doc.info.number
            case "CLIENT": return doc.info.client
            case "AUTHOR": return doc.info.author
            default: return doc.variable(n)
            }
        case "count":
            let t = args.first ?? "*"
            return "\(doc.allIDs.filter { ObjectQuery.typeMatches($0, t, doc: doc) }.count)"
        case "date":
            guard volatile else { return nil }
            let f = DateFormatter(); f.dateFormat = args.first.flatMap { $0.isEmpty ? nil : $0 } ?? "yyyy-MM-dd"
            return f.string(from: Date())
        case "filename": return doc.variable("DWGNAME") ?? doc.info.name
        case "posx", "posy", "northing", "easting":
            // Location of an object (a leader's arrow point); northing/easting add the survey offsets NORTHING0/EASTING0.
            guard let i = id(0), let e = doc.entity(i) else { return nil }
            let p: Vec2?
            switch e.geometry { case .leader(let l): p = l.points.first; case .point(let q): p = q; default: p = GeometryOps.grips(e.geometry).first }
            guard let q = p else { return nil }
            let n = name.lowercased()
            let v = n == "posx" ? q.x : n == "posy" ? q.y
                : n == "northing" ? q.y + (doc.variable("NORTHING0").flatMap(Double.init) ?? 0) : q.x + (doc.variable("EASTING0").flatMap(Double.init) ?? 0)
            return number(v, dim: 1)
        case "author": return doc.info.author
        case "plotdate", "savedate":
            if name.lowercased() == "savedate", let s = doc.variable("LASTSAVED") { return s }
            guard volatile else { return nil }
            let f = DateFormatter(); f.dateFormat = args.first.flatMap { $0.isEmpty ? nil : $0 } ?? "yyyy-MM-dd"
            return f.string(from: Date())
        case "sheetnumber", "sheetname", "sheettitle", "sheetcount", "revision":
            let li = layout ?? doc.variable("CTAB").flatMap { n in doc.layouts.firstIndex { $0.name == n } } ?? (doc.layouts.isEmpty ? nil : 0)
            switch name.lowercased() {
            case "sheetcount": return "\(doc.layouts.count)"
            case "revision": return li.flatMap { doc.layouts[$0].titleBlock["revision"] } ?? doc.variable("REVNUMBER")
            default: break
            }
            guard let i = li, doc.layouts.indices.contains(i) else { return nil }
            let l = doc.layouts[i]
            switch name.lowercased() {
            case "sheetnumber": return l.titleBlock["sheetNumber"] ?? l.titleBlock["Sheet"] ?? "\(i + 1)"
            case "sheetname": return l.titleBlock["sheetName"] ?? l.name
            default: return l.titleBlock["title"] ?? l.titleBlock["sheetName"] ?? l.name
            }
        default: return nil
        }
    }

    /// Evaluates a formula: {Field} references and field calls (Area(12), Var(USERR1)…) are replaced by their numbers,
    /// bare names by numeric system variables; then + - * / ^, parentheses and functions (sqrt, round…) are evaluated.
    public static func expression(_ s: String, doc: ArchiDocument, volatile: Bool = true, layout: Int? = nil) -> Double? {
        func number(_ v: String?) -> String? {
            guard let v = v else { return nil }
            if let d = Double(v) { return fmt(d, 12) }
            guard let r = v.range(of: #"-?\d+(\.\d+)?([eE][-+]?\d+)?"#, options: .regularExpression) else { return nil }
            return String(v[r])
        }
        var e = s
        // {Code} references.
        while let o = e.range(of: "{"), let c = e.range(of: "}", range: o.upperBound..<e.endIndex) {
            guard let v = number(evaluate(String(e[o.upperBound..<c.lowerBound]), doc: doc, volatile: volatile, layout: layout)) else { return nil }
            e.replaceSubrange(o.lowerBound..<c.upperBound, with: "(\(v))")
        }
        // Field calls written directly.
        let names = "area|length|perimeter|radius|diameter|height|measurement|prop|objprop|var|sysvar|count|sheetnumber|sheetcount"
        let rx = try! NSRegularExpression(pattern: "\\b(\(names))\\(([^()]*)\\)", options: .caseInsensitive)
        var guardN = 0
        while guardN < 100, let m = rx.firstMatch(in: e, range: NSRange(e.startIndex..., in: e)), let r = Range(m.range, in: e) {
            guardN += 1
            guard let v = number(evaluate(String(e[r]), doc: doc, volatile: volatile, layout: layout)) else { return nil }
            e.replaceSubrange(r, with: "(\(v))")
        }
        // Bare identifiers that are numeric system variables (USERR1, DIMSCALE…); math names are left to the evaluator.
        let known: Set<String> = ["pi", "e", "sqrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "exp", "round", "floor", "ceil", "r2d", "d2r"]
        let idRx = try! NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
        var out = ""
        var last = e.startIndex
        for m in idRx.matches(in: e, range: NSRange(e.startIndex..., in: e)) {
            guard let r = Range(m.range, in: e) else { continue }
            let word = String(e[r])
            // Skip exponent markers inside numbers (1e6).
            if word.lowercased().hasPrefix("e"), r.lowerBound > e.startIndex, e[e.index(before: r.lowerBound)].isNumber, Double("1" + word) != nil { continue }
            out += e[last..<r.lowerBound]
            if known.contains(word.lowercased()) { out += word }
            else if let v = doc.variable(word).flatMap(Double.init) { out += "(\(fmt(v, 12)))" }
            else { return nil }
            last = r.upperBound
        }
        out += e[last...]
        return CommandHelpers.evaluate(out)
    }

    /// Expands every %<...>% in a template. Unresolvable fields show "####".
    public static func expand(_ template: String, doc: ArchiDocument, previous: String? = nil, volatile: Bool = true, layout: Int? = nil) -> String {
        var out = "", rest = Substring(template)
        while let r = rest.range(of: "%<") {
            out += rest[..<r.lowerBound]
            guard let e = rest[r.upperBound...].range(of: ">%") else { out += rest[r.lowerBound...]; return out }
            let code = String(rest[r.upperBound..<e.lowerBound])
            if let v = evaluate(code, doc: doc, volatile: volatile, layout: layout) { out += v }
            else if !volatile, ["date", "plotdate", "savedate"].contains(where: { code.lowercased().hasPrefix($0) }), let prev = previous { return prev }
            else { out += placeholder }
            rest = rest[e.upperBound...]
        }
        return out + rest
    }

    /// Updates all field texts (non-volatile fields only unless `volatile`). Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument, ids: Set<EntityID>? = nil, volatile: Bool = false) -> Bool {
        var changed = false
        let snapshot = doc
        for i in doc.entities.indices {
            guard let tpl = doc.entities[i].props["field"] else { continue }
            if let ids = ids, !ids.contains(doc.entities[i].id) { continue }
            switch doc.entities[i].geometry {
            case .text(var t):
                let v = expand(tpl, doc: snapshot, previous: t.content, volatile: volatile)
                if v != t.content { t.content = v; doc.entities[i].geometry = .text(t); changed = true }
            case .leader(var l):
                let v = expand(tpl, doc: snapshot, previous: l.text, volatile: volatile)
                if v != l.text { l.text = v; doc.entities[i].geometry = .leader(l); changed = true }
            default: break
            }
        }
        // Paper-space fields (title blocks, sheet numbers) resolve against their own sheet.
        for li in doc.layouts.indices {
            for j in doc.layouts[li].entities.indices {
                guard let tpl = doc.layouts[li].entities[j].props["field"], case .text(var t) = doc.layouts[li].entities[j].geometry else { continue }
                if let ids = ids, !ids.contains(doc.layouts[li].entities[j].id) { continue }
                let v = expand(tpl, doc: snapshot, previous: t.content, volatile: volatile, layout: li)
                if v != t.content { t.content = v; doc.layouts[li].entities[j].geometry = .text(t); changed = true }
            }
        }
        return changed
    }
}

// MARK: - Annotative scaling

/// Annotative objects (prop "annotative" = "1") keep a paper height (prop "paperHeight", in paper mm);
/// their model height = paper height × current annotation scale (CANNOSCALE, e.g. "1:100").
public enum Annotative {
    public static let defaultScales = ["1:1", "1:2", "1:5", "1:10", "1:20", "1:25", "1:50", "1:100", "1:200", "1:250", "1:500", "1:1000", "2:1", "5:1", "10:1"]

    /// Model units per paper unit of a scale text ("1:100" → 100, "2:1" → 0.5, "100" → 100).
    public static func factor(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: " ", with: "")
        if let c = t.firstIndex(of: ":") ?? t.firstIndex(of: "=") {
            guard let a = Double(t[..<c]), let b = Double(t[t.index(after: c)...]), a > 0, b > 0 else { return nil }
            return b / a
        }
        if let v = Double(t), v > 0 { return v }
        return nil
    }
    public static func currentScale(_ doc: ArchiDocument) -> Double { doc.variable("CANNOSCALE").flatMap(factor) ?? 1 }
    public static func scaleList(_ doc: ArchiDocument) -> [String] {
        if let l = doc.variable("SCALELIST"), !l.isEmpty { return l.split(separator: ";").map(String.init) }
        return defaultScales
    }

    /// Model height for a paper height at the current scale.
    public static func modelHeight(paper: Double, doc: ArchiDocument) -> Double { paper * currentScale(doc) / doc.units.mm }

    /// Marks an entity annotative, deriving its paper height from the current model height.
    public static func makeAnnotative(_ e: inout Entity, doc: ArchiDocument) -> Bool {
        let h: Double
        switch e.geometry {
        case .text(let t): h = t.height
        case .leader(let l): h = l.textHeight
        case .table(let t): h = t.textHeight
        default: return false
        }
        e.props["annotative"] = "1"
        e.props["paperHeight"] = fmt(h * doc.units.mm / currentScale(doc), 8)
        return true
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        let s = currentScale(doc), mm = doc.units.mm
        for i in doc.entities.indices where doc.entities[i].props["annotative"] == "1" {
            guard let ph = doc.entities[i].props["paperHeight"].flatMap(Double.init), ph > 0 else { continue }
            let h = ph * s / mm
            switch doc.entities[i].geometry {
            case .text(var t) where abs(t.height - h) > 1e-9:
                t.height = h; doc.entities[i].geometry = .text(t); changed = true
            case .leader(var l) where abs(l.textHeight - h) > 1e-9:
                l.textHeight = h; doc.entities[i].geometry = .leader(l); changed = true
            case .table(var t) where abs(t.textHeight - h) > 1e-9:
                let k = h / t.textHeight
                t.textHeight = h; t.rowHeight *= k; t.columnWidths = t.columnWidths.map { $0 * k }
                doc.entities[i].geometry = .table(t); changed = true
            default: break
            }
        }
        return changed
    }
}

// MARK: - Table formulas

/// Table cell formulas stored in the entity prop "formulas" as lines "A1=SUM(A2:A4)" (cell=formula).
/// Supports + - * / ^, parentheses, cell references (A1, B12), ranges in SUM/AVERAGE/MIN/MAX/COUNT, ABS, ROUND, SQRT.
public enum TableFormulas {
    /// "B3" → (row 2, col 1) zero-based.
    public static func cellIndex(_ ref: String) -> (row: Int, col: Int)? {
        let t = ref.uppercased().trimmingCharacters(in: .whitespaces)
        let letters = t.prefix { $0.isLetter }, digits = t.dropFirst(letters.count)
        guard !letters.isEmpty, letters.count <= 3, let r = Int(digits), r >= 1 else { return nil }
        var c = 0
        for ch in letters { guard let a = ch.asciiValue else { return nil }; c = c * 26 + Int(a - 64) }
        return (r - 1, c - 1)
    }
    public static func cellName(row: Int, col: Int) -> String {
        var c = col + 1, s = ""
        while c > 0 { let m = (c - 1) % 26; s = String(UnicodeScalar(UInt8(65 + m))) + s; c = (c - 1) / 26 }
        return s + "\(row + 1)"
    }

    public static func formulas(_ e: Entity) -> [String: String] {
        var out: [String: String] = [:]
        for line in (e.props["formulas"] ?? "").split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            out[line[..<eq].uppercased()] = String(line[line.index(after: eq)...])
        }
        return out
    }
    public static func setFormulas(_ e: inout Entity, _ f: [String: String]) {
        if f.isEmpty { e.props["formulas"] = nil; return }
        e.props["formulas"] = f.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    /// Evaluates a formula ("=SUM(A1:A3)*2") against the cells.
    public static func evaluate(_ formula: String, cells: [[String]]) -> Double? {
        var f = formula.trimmingCharacters(in: .whitespaces)
        if f.hasPrefix("=") { f.removeFirst() }
        var p = Parser(c: Array(f.replacingOccurrences(of: " ", with: "").uppercased()), cells: cells)
        guard let v = p.expr(), p.i == p.c.count, v.isFinite else { return nil }
        return v
    }

    struct Parser {
        var c: [Character]; var i = 0; let cells: [[String]]
        init(c: [Character], cells: [[String]]) { self.c = c; self.cells = cells }
        func cellValue(_ r: Int, _ col: Int) -> Double? {
            guard r >= 0, r < cells.count, col >= 0, col < cells[r].count else { return nil }
            let s = cells[r][col].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            return Double(s)
        }
        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "-" { let op = c[i]; i += 1; guard let r = term() else { return nil }; v = op == "+" ? v + r : v - r }
            return v
        }
        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < c.count, c[i] == "*" || c[i] == "/" { let op = c[i]; i += 1; guard let r = power() else { return nil }; v = op == "*" ? v * r : v / r }
            return v
        }
        mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if i < c.count, c[i] == "^" { i += 1; guard let e = power() else { return nil }; return pow(b, e) }
            return b
        }
        mutating func unary() -> Double? {
            if i < c.count, c[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < c.count, c[i] == "+" { i += 1; return unary() }
            return atom()
        }
        mutating func ident() -> String {
            var s = ""
            while i < c.count, c[i].isLetter || c[i].isNumber { s.append(c[i]); i += 1 }
            return s
        }
        /// Arguments: expressions or ranges, flattened to numbers.
        mutating func args() -> [Double]? {
            guard i < c.count, c[i] == "(" else { return nil }
            i += 1
            var out: [Double] = []
            while i < c.count, c[i] != ")" {
                let save = i
                let a = ident()
                if i < c.count, c[i] == ":", let s = TableFormulas.cellIndex(a) {
                    i += 1
                    let b = ident()
                    guard let e = TableFormulas.cellIndex(b) else { return nil }
                    for r in min(s.row, e.row)...max(s.row, e.row) {
                        for col in min(s.col, e.col)...max(s.col, e.col) { if let v = cellValue(r, col) { out.append(v) } }
                    }
                } else {
                    i = save
                    guard let v = expr() else { return nil }
                    out.append(v)
                }
                if i < c.count, c[i] == "," || c[i] == ";" { i += 1 }
            }
            guard i < c.count else { return nil }
            i += 1
            return out
        }
        mutating func atom() -> Double? {
            guard i < c.count else { return nil }
            if c[i] == "(" { i += 1; let v = expr(); guard i < c.count, c[i] == ")" else { return nil }; i += 1; return v }
            if c[i].isNumber || c[i] == "." {
                var s = ""
                while i < c.count, c[i].isNumber || c[i] == "." { s.append(c[i]); i += 1 }
                return Double(s)
            }
            if c[i].isLetter {
                let name = ident()
                if i < c.count, c[i] == "(" {
                    guard let a = args() else { return nil }
                    switch name {
                    case "SUM": return a.reduce(0, +)
                    case "AVERAGE", "AVG": return a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count)
                    case "MIN": return a.min() ?? 0
                    case "MAX": return a.max() ?? 0
                    case "COUNT": return Double(a.count)
                    case "ABS": return a.first.map(abs)
                    case "SQRT": return a.first.map { $0.squareRoot() }
                    case "ROUND":
                        guard let x = a.first else { return nil }
                        let n = a.count > 1 ? a[1] : 0
                        let k = pow(10, n); return (x * k).rounded() / k
                    default: return nil
                    }
                }
                if name == "PI" { return .pi }
                guard let idx = TableFormulas.cellIndex(name) else { return nil }
                return cellValue(idx.row, idx.col) ?? 0
            }
            return nil
        }
    }

    /// Recomputes formula cells of all tables (several passes so formulas can use other formulas).
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices where doc.entities[i].props["formulas"] != nil {
            guard case .table(var t) = doc.entities[i].geometry else { continue }
            let fs = formulas(doc.entities[i])
            let before = t.cells
            for _ in 0..<max(1, min(fs.count, 20)) {
                var pass = false
                for (ref, f) in fs {
                    guard let (r, c) = cellIndex(ref), r < t.cells.count, c < t.columnWidths.count else { continue }
                    while t.cells[r].count <= c { t.cells[r].append("") }
                    let v = evaluate(f, cells: t.cells).map { fmt($0, 6) } ?? "#ERR"
                    if t.cells[r][c] != v { t.cells[r][c] = v; pass = true }
                }
                if !pass { break }
            }
            if t.cells != before { doc.entities[i].geometry = .table(t); changed = true }
        }
        return changed
    }

    /// Table contents as CSV.
    public static func csv(_ t: TableGeom) -> String {
        t.cells.map { row in
            row.map { v in v.contains(",") || v.contains("\"") || v.contains("\n") ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }
}
