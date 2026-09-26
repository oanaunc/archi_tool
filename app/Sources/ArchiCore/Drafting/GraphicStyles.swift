// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Graphic resolution layered on top of the ordinary ByLayer/ByBlock properties of drafting objects:
///
/// - Line styles (LAY-034): named weight/colour/pattern sets. An object uses one through its `lineStyle` prop, or
///   ByLayer through the layer's line style (`LAYERLINESTYLE:<layer>`). Stored as `LINESTYLE:<NAME>` variables.
/// - Lineweight tables by scale (LAY-035): `LWTABLE` = "50=1;100=0.7;200=0.5" scales every lineweight by the factor of
///   the largest listed scale denominator not above the current annotation scale (CANNOSCALE).
/// - Pen sets (LAY-036): `PENSET:<NAME>` maps pen numbers (the object's resolved colour index) to a weight and an
///   optional colour; the pen set named by `PENSET` applies to plots/PDF (and on screen when `PENSETDISPLAY` = 1).
/// - Graphic overrides by filter (LAY-037): rules in `DRAFTFILTERS` (JSON) that match objects by layer, type, colour,
///   linetype, lineweight or any property and hide them or override colour/lineweight/halftone.
///
/// All are document variables, so they persist in .archi files and follow undo. Integration: `DraftRendering.items`
/// asks `GraphicStyles.items` first.
public enum GraphicStyles {
    static let guardProp = "\u{1}graphicStyles"
    static let layerStackKey = "archi.graphicStylesLayers"
    public static let lineStyleProp = "lineStyle"
    public static let lineStylePrefix = "LINESTYLE:"
    public static let layerLineStylePrefix = "LAYERLINESTYLE:"
    public static let penSetPrefix = "PENSET:"
    public static let currentPenSetVariable = "PENSET"
    public static let penSetDisplayVariable = "PENSETDISPLAY"
    public static let lineweightTableVariable = "LWTABLE"
    public static let filtersVariable = "DRAFTFILTERS"

    // MARK: Line styles

    public struct LineStyle: Hashable {
        public var name: String
        public var color: ColorRef?
        public var lineweight: Double?
        public var linetype: String?
        public init(name: String, color: ColorRef? = nil, lineweight: Double? = nil, linetype: String? = nil) {
            self.name = name; self.color = color; self.lineweight = lineweight; self.linetype = linetype
        }
        public var encoded: String {
            var p: [String] = []
            if let c = color { p.append("color=" + c.text) }
            if let w = lineweight { p.append("lw=" + fmt(w, 4)) }
            if let l = linetype { p.append("lt=" + l) }
            return p.joined(separator: ";")
        }
        public init(name: String, encoded: String) {
            self.name = name
            for part in encoded.split(separator: ";") {
                guard let eq = part.firstIndex(of: "=") else { continue }
                let k = part[..<eq].lowercased(), v = String(part[part.index(after: eq)...])
                switch k {
                case "color": color = ColorRef.parse(v)
                case "lw": lineweight = Double(v).flatMap { $0 >= 0 ? $0 : nil }
                case "lt": linetype = v.isEmpty ? nil : v
                default: break
                }
            }
        }
    }

    public static func lineStyleNames(_ doc: ArchiDocument) -> [String] {
        doc.variables.keys.filter { $0.hasPrefix(lineStylePrefix) }.map { String($0.dropFirst(lineStylePrefix.count)) }.sorted()
    }
    public static func lineStyle(_ name: String, doc: ArchiDocument) -> LineStyle? {
        guard let v = doc.variable(lineStylePrefix + name) else { return nil }
        let display = doc.variable("LINESTYLENAME:" + name) ?? name
        return LineStyle(name: display, encoded: v)
    }
    public static func setLineStyle(_ s: LineStyle, doc: inout ArchiDocument) {
        doc.setVariable(lineStylePrefix + s.name, s.encoded)
        doc.setVariable("LINESTYLENAME:" + s.name, s.name)
    }
    public static func deleteLineStyle(_ name: String, doc: inout ArchiDocument) {
        doc.variables[(lineStylePrefix + name).uppercased()] = nil
        doc.variables[("LINESTYLENAME:" + name).uppercased()] = nil
        for (k, v) in doc.variables where k.hasPrefix(layerLineStylePrefix) && v.caseInsensitiveCompare(name) == .orderedSame { doc.variables[k] = nil }
        for i in doc.entities.indices where doc.entities[i].props[lineStyleProp]?.caseInsensitiveCompare(name) == .orderedSame { doc.entities[i].props[lineStyleProp] = nil }
    }
    public static func layerLineStyle(_ layer: String, doc: ArchiDocument) -> String? { doc.variable(layerLineStylePrefix + layer) }
    public static func setLayerLineStyle(_ layer: String, _ style: String?, doc: inout ArchiDocument) {
        let k = (layerLineStylePrefix + layer).uppercased()
        if let s = style { doc.variables[k] = s } else { doc.variables[k] = nil }
    }

    /// Line style of an object: its own `lineStyle` prop, or ByLayer the layer's (layer "0" objects in blocks use the
    /// insert's layer, passed as `layer`).
    public static func resolvedLineStyle(_ e: Entity, layer: String? = nil, doc: ArchiDocument) -> LineStyle? {
        let own = e.props[lineStyleProp]
        if let o = own, o.caseInsensitiveCompare("ByLayer") != .orderedSame { return lineStyle(o, doc: doc) }
        return layerLineStyle(layer ?? e.layer, doc: doc).flatMap { lineStyle($0, doc: doc) }
    }

    // MARK: Pen sets

    public struct Pen: Hashable {
        public var lineweight: Double
        public var color: RGBA?
        public init(lineweight: Double, color: RGBA? = nil) { self.lineweight = lineweight; self.color = color }
    }

    public static func penSetNames(_ doc: ArchiDocument) -> [String] {
        doc.variables.keys.filter { $0.hasPrefix(penSetPrefix) }.map { String($0.dropFirst(penSetPrefix.count)) }.sorted()
    }
    /// Pens of a pen set: "pen=weight[,color]" entries separated by ';'.
    public static func penSet(_ name: String, doc: ArchiDocument) -> [Int: Pen]? {
        guard let v = doc.variable(penSetPrefix + name) else { return nil }
        return parsePens(v)
    }
    public static func parsePens(_ v: String) -> [Int: Pen] {
        var out: [Int: Pen] = [:]
        for part in v.split(separator: ";") {
            guard let eq = part.firstIndex(of: "="), let n = Int(part[..<eq].trimmingCharacters(in: .whitespaces)), (1...255).contains(n) else { continue }
            let f = part[part.index(after: eq)...].split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let w = f.first.flatMap(Double.init), w >= 0 else { continue }
            var pen = Pen(lineweight: w)
            if f.count > 1, let c = ColorRef.parse(f[1]) {
                switch c {
                case .aci(let i): pen.color = aciColor(i)
                case .rgb(let r, let g, let b): pen.color = RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
                default: break
                }
            }
            out[n] = pen
        }
        return out
    }
    public static func encodePens(_ pens: [Int: Pen]) -> String {
        pens.keys.sorted().map { n in
            let p = pens[n]!
            var s = "\(n)=" + fmt(p.lineweight, 4)
            if let c = p.color { s += "," + ColorRef.rgb(UInt8((c.r * 255).rounded()), UInt8((c.g * 255).rounded()), UInt8((c.b * 255).rounded())).text }
            return s
        }.joined(separator: ";")
    }
    public static func setPenSet(_ name: String, _ pens: [Int: Pen], doc: inout ArchiDocument) { doc.setVariable(penSetPrefix + name, encodePens(pens)) }

    /// Pen set in effect for a drawing pass (plots and PDF; the screen only with PENSETDISPLAY = 1).
    public static func activePenSet(_ doc: ArchiDocument, _ options: DrawOptions) -> [Int: Pen]? {
        guard let n = doc.variable(currentPenSetVariable), !n.isEmpty, n.lowercased() != "none" else { return nil }
        guard options.forPaper || doc.variable(penSetDisplayVariable) == "1" else { return nil }
        return cachedPens(n, doc)
    }

    /// Pen number of an object: its colour index, or the nearest index to its resolved colour.
    public static func penNumber(_ e: Entity, resolved: RGBA) -> Int {
        if case .aci(let i) = e.color, (1...255).contains(i) { return i }
        return DXFColors.nearest(resolved)
    }

    // MARK: Lineweight tables by scale

    /// Parsed LWTABLE rows (scale denominator, factor), sorted.
    public static func lineweightTable(_ doc: ArchiDocument) -> [(scale: Double, factor: Double)] {
        guard let v = doc.variable(lineweightTableVariable) else { return [] }
        return parseTable(v)
    }
    public static func parseTable(_ v: String) -> [(scale: Double, factor: Double)] {
        v.split(separator: ";").compactMap { part -> (Double, Double)? in
            guard let eq = part.lastIndex(of: "=") else { return nil }
            let key = String(part[..<eq]).trimmingCharacters(in: .whitespaces)
            guard let s = Annotative.factor(key.contains(":") ? key : "1:" + key), let f = Double(part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)), f > 0 else { return nil }
            return (s, f)
        }.sorted { $0.0 < $1.0 }
    }
    /// Lineweight factor at a scale denominator (nil when there is no table).
    public static func lineweightFactor(_ table: [(scale: Double, factor: Double)], scale: Double) -> Double? {
        guard let first = table.first else { return nil }
        return table.last { $0.scale <= scale + 1e-9 }?.factor ?? first.factor
    }

    // MARK: Filters

    public struct FilterRule: Codable, Hashable {
        public var name: String
        /// Object types the rule applies to (line, circle, text, insert …; empty = all).
        public var types: [String]
        /// layer, type, color, linetype, lineweight or a property key.
        public var field: String
        /// =, !=, contains, !contains, begins, ends, <, <=, >, >=
        public var op: String
        public var value: String
        public var override: GraphicOverride
        public var enabled: Bool
        public init(name: String, types: [String] = [], field: String, op: String, value: String, override: GraphicOverride, enabled: Bool = true) {
            self.name = name; self.types = types; self.field = field; self.op = op; self.value = value; self.override = override; self.enabled = enabled
        }
    }

    public static let ops = ["=", "!=", "contains", "!contains", "begins", "ends", "<", "<=", ">", ">="]

    public static func filters(_ doc: ArchiDocument) -> [FilterRule] {
        guard let v = doc.variable(filtersVariable) else { return [] }
        return cachedFilters(v)
    }
    public static func setFilters(_ f: [FilterRule], doc: inout ArchiDocument) {
        if f.isEmpty { doc.variables[filtersVariable] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(f), let s = String(data: d, encoding: .utf8) { doc.setVariable(filtersVariable, s) }
    }

    /// Value of a filter field for an object.
    public static func fieldValue(_ field: String, _ e: Entity, doc: ArchiDocument) -> String? {
        switch field.lowercased() {
        case "layer": return e.layer
        case "type": return e.geometry.typeName
        case "color", "colour": return e.color.text
        case "linetype": return e.linetype ?? "ByLayer"
        case "lineweight": return e.lineweight.map { fmt($0, 4) } ?? "ByLayer"
        case "linestyle": return e.props[lineStyleProp] ?? "ByLayer"
        default: return e.props[field] ?? e.props.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
        }
    }

    public static func matches(_ r: FilterRule, _ e: Entity, doc: ArchiDocument) -> Bool {
        guard r.enabled else { return false }
        if !r.types.isEmpty && !r.types.contains(where: { $0.caseInsensitiveCompare(e.geometry.typeName) == .orderedSame }) { return false }
        let v = fieldValue(r.field, e, doc: doc)
        let a = (v ?? "").lowercased(), b = r.value.lowercased()
        switch r.op.lowercased() {
        case "=", "==", "equals": return v != nil && a == b
        case "!=", "<>", "notequals": return a != b
        case "contains": return a.contains(b)
        case "!contains": return !a.contains(b)
        case "begins": return a.hasPrefix(b)
        case "ends": return a.hasSuffix(b)
        default:
            guard let x = v.flatMap({ Double($0) }), let y = Double(r.value) else { return false }
            switch r.op { case "<": return x < y; case "<=": return x <= y; case ">": return x > y; case ">=": return x >= y; default: return false }
        }
    }

    /// Combined override of the enabled rules matching an object (later rules win); nil when none match.
    public static func filterOverride(_ e: Entity, doc: ArchiDocument) -> GraphicOverride? {
        let fs = filters(doc)
        guard !fs.isEmpty else { return nil }
        var o: GraphicOverride?
        for r in fs where matches(r, e, doc: doc) { o = (o ?? GraphicOverride()).merged(r.override) }
        return o
    }

    // MARK: Caches (drawing passes run on several threads)

    static let lock = NSLock()
    nonisolated(unsafe) static var filterCache: [String: [FilterRule]] = [:]
    nonisolated(unsafe) static var penCache: [String: [Int: Pen]] = [:]

    static func cachedFilters(_ json: String) -> [FilterRule] {
        lock.lock(); defer { lock.unlock() }
        if let c = filterCache[json] { return c }
        let f = (json.data(using: .utf8).flatMap { try? JSONDecoder().decode([FilterRule].self, from: $0) }) ?? []
        if filterCache.count > 32 { filterCache.removeAll() }
        filterCache[json] = f
        return f
    }
    static func cachedPens(_ name: String, _ doc: ArchiDocument) -> [Int: Pen]? {
        guard let v = doc.variable(penSetPrefix + name) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let c = penCache[v] { return c }
        let p = parsePens(v)
        if penCache.count > 32 { penCache.removeAll() }
        penCache[v] = p
        return p
    }

    // MARK: Rendering

    static func rgb(_ c: RGBA) -> ColorRef { .rgb(UInt8((max(0, min(1, c.r)) * 255).rounded()), UInt8((max(0, min(1, c.g)) * 255).rounded()), UInt8((max(0, min(1, c.b)) * 255).rounded())) }

    static func resolve(_ c: ColorRef, layer: String, doc: ArchiDocument, fallback: RGBA) -> RGBA {
        switch c {
        case .byLayer: return doc.layer(named: layer)?.color ?? fallback
        case .byBlock: return fallback
        case .aci(let i): return (i == 0 || i == 256) ? fallback : aciColor(i)
        case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        }
    }

    /// Draw items for an object with a line style, pen set, lineweight table or filter override; nil when none applies.
    public static func items(_ e: Entity, doc: ArchiDocument, options: DrawOptions, color: RGBA, lineweight: Double) -> [DrawItem]? {
        guard e.props[guardProp] == nil else { return nil }
        let isInsert: Bool
        if case .insert = e.geometry { isInsert = true } else { isInsert = false }
        let stack = Thread.current.threadDictionary[layerStackKey] as? [String] ?? []
        let effectiveLayer = (e.layer == "0" ? stack.last : nil) ?? e.layer
        if isInsert, filterOverride(e, doc: doc) == nil, doc.variables.keys.contains(where: { $0.hasPrefix(layerLineStylePrefix) }) {
            // Layer "0" objects inside the block take the insert's layer (and so its line style).
            var plain = e
            plain.props[guardProp] = "1"
            Thread.current.threadDictionary[layerStackKey] = stack + [effectiveLayer]
            defer { Thread.current.threadDictionary[layerStackKey] = stack }
            return DraftRendering.items(plain, doc: doc, options: options, color: color, lineweight: lineweight)
                ?? DrawListBuilder.items(plain, doc: doc, options: options, inherit: DrawListBuilder.Inherit(color: color, lineweight: lineweight, layer: effectiveLayer))
        }
        let ls = isInsert ? nil : resolvedLineStyle(e, layer: effectiveLayer, doc: doc)
        let pens = isInsert ? nil : activePenSet(doc, options)
        let lwf = isInsert ? nil : lineweightFactor(lineweightTable(doc), scale: Annotative.currentScale(doc))
        let ov = filterOverride(e, doc: doc)
        guard ls != nil || pens != nil || lwf != nil || ov != nil else { return nil }
        var plain = e
        plain.props[guardProp] = "1"
        var col = color, lw = lineweight
        if let s = ls {
            if let c = s.color { col = resolve(c, layer: effectiveLayer, doc: doc, fallback: color) }
            if let w = s.lineweight { lw = w }
            if let lt = s.linetype { plain.linetype = lt }
        }
        plain.color = rgb(col)
        plain.lineweight = lw
        var out = DrawListBuilder.items(plain, doc: doc, options: options, inherit: DrawListBuilder.Inherit(color: col, lineweight: lw, layer: e.layer))
        if let pens = pens, let pen = pens[penNumber(e, resolved: col)] {
            out = out.map { it in
                switch it {
                case .stroke(let p, let c, var st): st.lineweight = pen.lineweight; if let pc = pen.color { st.color = RGBA(pc.r, pc.g, pc.b, st.color.a) }; return .stroke(points: p, closed: c, style: st)
                case .fill(let l, let c): return pen.color.map { .fill(loops: l, color: RGBA($0.r, $0.g, $0.b, c.a)) } ?? it
                case .text(let t, let f, let c): return pen.color.map { .text(t, font: f, color: RGBA($0.r, $0.g, $0.b, c.a)) } ?? it
                case .image: return it
                }
            }
        }
        if let f = lwf, abs(f - 1) > 1e-12 {
            out = out.map { it in
                if case .stroke(let p, let c, var st) = it { st.lineweight *= f; return .stroke(points: p, closed: c, style: st) }
                return it
            }
        }
        if let o = ov { return VisibilityGraphics.apply(o, to: out) ?? [] }
        return out
    }
}
