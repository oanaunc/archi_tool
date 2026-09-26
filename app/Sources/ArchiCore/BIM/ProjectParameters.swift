// Oanarina Archi Tool — GPL-3.0-or-later
// Project parameters (PAR-023) and shared parameter files (PAR-022): parameters added to element categories, with
// defaults or formulas over the element's values; they appear in schedules, tags and view filters, and element
// dimension bindings (props gp.<field>) can use them so they drive geometry.
import Foundation

public enum ProjectParameters {
    public static func applies(_ p: ProjectParameter, to el: BIMElement) -> Bool {
        p.categories.isEmpty || p.categories.contains { VisibilityGraphics.norm($0) == VisibilityGraphics.norm(VisibilityGraphics.category(el)) }
    }

    public static func parameter(_ name: String, doc: ArchiDocument) -> ProjectParameter? {
        doc.projectParameters.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Value of a project parameter for an element: the instance value (props), else the formula over the element's
    /// fields (other parameters and properties), else the default. nil when the parameter does not apply.
    public static func value(_ name: String, of el: BIMElement, doc: ArchiDocument, depth: Int = 0) -> String? {
        guard let p = parameter(name, doc: doc), applies(p, to: el) else { return nil }
        if let v = el.props.first(where: { $0.key.caseInsensitiveCompare(p.name) == .orderedSame })?.value { return v }
        if let f = p.formula, depth < 8 {
            var vars: [String: Double] = [:]
            for id in FamilyExpr.identifiers(f) {
                let s = (value(id, of: el, doc: doc, depth: depth + 1)) ?? Schedules.value(id, Schedules.Obj(id: el.id, element: el), doc: doc)
                if let x = Double(s) { vars[id] = x }
            }
            for (k, x) in GlobalParameters.values(doc) where vars[k] == nil { vars[k] = x }
            if let x = FamilyExpr.evaluate(f, vars) { return fmt(x, 3) }
            return "?"
        }
        return p.value
    }

    /// Numeric project parameter values of an element (lower-cased names), for dimension bindings.
    public static func numericValues(_ el: BIMElement, doc: ArchiDocument) -> [String: Double] {
        var out: [String: Double] = [:]
        for p in doc.projectParameters where p.kind.isNumeric && applies(p, to: el) {
            if let s = value(p.name, of: el, doc: doc), let x = Double(s) { out[p.name.lowercased()] = x }
        }
        return out
    }

    // MARK: Shared parameter files (tab-separated, Revit-like)

    static func dataType(_ k: FamilyParameterKind) -> String {
        switch k { case .yesNo: return "YESNO"; case .familyType: return "FAMILYTYPE"; default: return k.rawValue.uppercased() }
    }
    static func kind(_ s: String) -> FamilyParameterKind {
        switch s.uppercased() { case "YESNO": return .yesNo; case "FAMILYTYPE": return .familyType
        default: return FamilyParameterKind(rawValue: s.lowercased()) ?? .text }
    }

    /// Shared parameter file text for the given parameters (each gets a GUID if it has none).
    public static func sharedFile(_ ps: [ProjectParameter]) -> String {
        var lines = ["# Oanarina Archi Tool shared parameters", "*PARAM\tGUID\tNAME\tDATATYPE\tGROUP"]
        for p in ps { lines.append(["PARAM", p.guid ?? UUID().uuidString, p.name, dataType(p.kind), p.group ?? "General"].joined(separator: "\t")) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parameter definitions in a shared parameter file.
    public static func parseShared(_ text: String) -> [ProjectParameter] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 4, c[0] == "PARAM", !c[2].isEmpty else { return nil }
            return ProjectParameter(name: c[2], kind: kind(c[3]), group: c.count > 4 ? c[4] : nil, guid: c[1])
        }
    }

    /// Adds (or updates, matched by GUID then name) shared parameters bound to categories. Returns the number added.
    @discardableResult
    public static func bind(_ defs: [ProjectParameter], categories: [String], doc: inout ArchiDocument) -> Int {
        var n = 0
        for var d in defs {
            d.categories = categories
            if let i = doc.projectParameters.firstIndex(where: { ($0.guid != nil && $0.guid == d.guid) || $0.name.caseInsensitiveCompare(d.name) == .orderedSame }) {
                d.value = doc.projectParameters[i].value; d.formula = doc.projectParameters[i].formula
                doc.projectParameters[i] = d
            } else { doc.projectParameters.append(d); n += 1 }
        }
        return n
    }
}
