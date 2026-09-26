// Oanarina Archi Tool — GPL-3.0-or-later
// Object styles (LAY-033, Revit "Object Styles"): project-wide graphics per BIM category — projection and cut line
// weights, line colour, cut poché colour and cut pattern. They are the defaults every plan and section draws with;
// view overrides (VG / filters, DOC-020/021) still win on top. Stored in the document as OBJECTSTYLES (JSON keyed by
// category), so they are saved with the .archi file and older files simply have none.
import Foundation

public struct ObjectStyle: Codable, Hashable {
    /// Plotted weight (mm) of projection lines (element outlines seen, not cut).
    public var projectionLineweight: Double?
    /// Plotted weight (mm) of cut lines (outline where the cut plane passes through the element).
    public var cutLineweight: Double?
    /// Line colour of the category.
    public var color: RGBA?
    /// Colour of cut poché fills.
    public var cutFill: RGBA?
    /// Cut hatch pattern (a HatchPatterns name, or SOLID) replacing the materials' cut patterns.
    public var cutPattern: String?
    public init(projectionLineweight: Double? = nil, cutLineweight: Double? = nil, color: RGBA? = nil, cutFill: RGBA? = nil, cutPattern: String? = nil) {
        self.projectionLineweight = projectionLineweight; self.cutLineweight = cutLineweight; self.color = color
        self.cutFill = cutFill; self.cutPattern = cutPattern
    }
    public var isEmpty: Bool { projectionLineweight == nil && cutLineweight == nil && color == nil && cutFill == nil && cutPattern == nil }
    /// `other` wins where it sets a value.
    public func merged(_ other: ObjectStyle) -> ObjectStyle {
        ObjectStyle(projectionLineweight: other.projectionLineweight ?? projectionLineweight, cutLineweight: other.cutLineweight ?? cutLineweight,
                    color: other.color ?? color, cutFill: other.cutFill ?? cutFill, cutPattern: other.cutPattern ?? cutPattern)
    }
}

public enum ObjectStyles {
    public static let key = "OBJECTSTYLES"
    /// Categories listed by OBJECTSTYLES (any VisibilityGraphics category name is accepted).
    public static let categories = ["wall", "door", "window", "opening", "slab", "ceiling", "column", "beam", "roof", "stair", "railing",
                                    "room", "area", "curtainwall", "component", "grid", "part"]

    private static var cache: (raw: String, styles: [String: ObjectStyle])?

    public static func all(_ doc: ArchiDocument) -> [String: ObjectStyle] {
        guard let s = doc.variable(key), !s.isEmpty else { return [:] }
        if let c = cache, c.raw == s { return c.styles }
        guard let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([String: ObjectStyle].self, from: d) else { return [:] }
        let styles = Dictionary(v.map { (VisibilityGraphics.norm($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        cache = (s, styles)
        return styles
    }

    public static func setAll(_ v: [String: ObjectStyle], doc: inout ArchiDocument) {
        let clean = v.filter { !$0.value.isEmpty }
        if clean.isEmpty { doc.variables[key] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        doc.setVariable(key, String(decoding: (try? enc.encode(clean)) ?? Data(), as: UTF8.self))
    }

    public static func style(_ category: String, doc: ArchiDocument) -> ObjectStyle? {
        let s = all(doc)[VisibilityGraphics.norm(category)]
        return s?.isEmpty == false ? s : nil
    }

    public static func style(for el: BIMElement, doc: ArchiDocument) -> ObjectStyle? {
        guard doc.variable(key) != nil else { return nil }
        return style(VisibilityGraphics.category(el), doc: doc)
    }

    /// Applies a style to plan items: strokes drawn at the cut weight take the cut weight, projection-weight strokes the
    /// projection weight (fine, hidden and annotation lines keep theirs); line colour to strokes and text; the cut fill
    /// to solid fills.
    public static func apply(_ s: ObjectStyle, to items: [DrawItem]) -> [DrawItem] {
        items.map { it in
            switch it {
            case .stroke(let p, let c, var st):
                if st.lineweight >= PlanRepresentation.lwCut - 1e-9 { if let w = s.cutLineweight { st.lineweight = w } }
                else if abs(st.lineweight - PlanRepresentation.lwProj) < 1e-9 { if let w = s.projectionLineweight { st.lineweight = w } }
                if let col = s.color { st.color = RGBA(col.r, col.g, col.b, st.color.a) }
                return .stroke(points: p, closed: c, style: st)
            case .fill(let l, let c):
                guard let f = s.cutFill else { return it }
                return .fill(loops: l, color: RGBA(f.r, f.g, f.b, c.a))
            case .text(let t, let f, let c):
                guard let col = s.color else { return it }
                return .text(t, font: f, color: RGBA(col.r, col.g, col.b, c.a))
            case .image: return it
            }
        }
    }

    /// Parses "cut:0.7; proj:0.35; color:red; fill:0.3,0.3,0.3; pattern:ANSI31" (parts separated by ';').
    public static func parse(_ spec: String) -> ObjectStyle? {
        var o = ObjectStyle()
        for part in spec.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[1].isEmpty else { return nil }
            let k = kv[0].lowercased(), v = kv[1]
            switch k {
            case "cut", "cutlw", "cutlineweight":
                guard let x = Double(v), x > 0, x <= 5 else { return nil }; o.cutLineweight = x
            case "proj", "projection", "projlw", "projectionlineweight", "lw":
                guard let x = Double(v), x > 0, x <= 5 else { return nil }; o.projectionLineweight = x
            case "color", "colour":
                guard let c = VisibilityGraphics.named(v.lowercased()) ?? ScheduleCommands.color(v) else { return nil }; o.color = c
            case "fill", "cutfill":
                guard let c = VisibilityGraphics.named(v.lowercased()) ?? ScheduleCommands.color(v) else { return nil }; o.cutFill = c
            case "pattern", "cutpattern":
                let n = v.uppercased()
                guard n == "SOLID" || HatchPatterns.names.contains(n) else { return nil }
                o.cutPattern = n
            default: return nil
            }
        }
        return o
    }

    /// One-line description of a style.
    public static func describe(_ s: ObjectStyle) -> String {
        var parts: [String] = []
        if let w = s.projectionLineweight { parts.append("proj \(fmt(w))") }
        if let w = s.cutLineweight { parts.append("cut \(fmt(w))") }
        if let c = s.color { parts.append("colour \(fmt(c.r)),\(fmt(c.g)),\(fmt(c.b))") }
        if let c = s.cutFill { parts.append("fill \(fmt(c.r)),\(fmt(c.g)),\(fmt(c.b))") }
        if let p = s.cutPattern { parts.append("pattern \(p)") }
        return parts.isEmpty ? "(defaults)" : parts.joined(separator: ", ")
    }
    static func fmt(_ x: Double) -> String { String(format: "%g", (x * 1000).rounded() / 1000) }
}
