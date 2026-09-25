// Oanarina Archi Tool — GPL-3.0-or-later
// Information Delivery Specification (buildingSMART IDS 1.0) checking of IFC files: specifications with entity,
// attribute, property and material facets; values as simpleValue or xs:restriction (enumeration, pattern,
// min/max inclusive/exclusive, length); cardinality required / optional / prohibited. Classification and partOf
// facets are reported as unsupported.
import Foundation

public struct IDSValue: Hashable {
    public var simple: String?
    public var enumeration: [String] = []
    public var pattern: String?
    public var minInclusive: Double?, maxInclusive: Double?, minExclusive: Double?, maxExclusive: Double?
    public var length: Int?
    public var isEmpty: Bool { simple == nil && enumeration.isEmpty && pattern == nil && minInclusive == nil && maxInclusive == nil && minExclusive == nil && maxExclusive == nil && length == nil }

    public func matches(_ v: String, caseInsensitive: Bool = false) -> Bool {
        if let s = simple {
            if caseInsensitive ? s.caseInsensitiveCompare(v) != .orderedSame : s != v {
                // Numbers compare by value; booleans by meaning.
                if let a = Double(s), let b = Double(v) { if abs(a - b) > 1e-9 * max(1, abs(a)) { return false } }
                else if ["true", "false"].contains(s.lowercased()) && ["true", "false", "t", "f"].contains(v.lowercased()) { if s.lowercased().first != v.lowercased().first { return false } }
                else { return false }
            }
        }
        if !enumeration.isEmpty && !enumeration.contains(where: { caseInsensitive ? $0.caseInsensitiveCompare(v) == .orderedSame : $0 == v }) { return false }
        if let p = pattern, let re = try? NSRegularExpression(pattern: "^(?:" + p + ")$") {
            if re.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) == nil { return false }
        }
        if minInclusive != nil || maxInclusive != nil || minExclusive != nil || maxExclusive != nil {
            guard let d = Double(v) else { return false }
            if let m = minInclusive, d < m { return false }
            if let m = maxInclusive, d > m { return false }
            if let m = minExclusive, d <= m { return false }
            if let m = maxExclusive, d >= m { return false }
        }
        if let l = length, v.count != l { return false }
        return true
    }
    public var description: String {
        if let s = simple { return "'\(s)'" }
        var parts: [String] = []
        if !enumeration.isEmpty { parts.append("one of " + enumeration.joined(separator: "/")) }
        if let p = pattern { parts.append("matching /\(p)/") }
        if let m = minInclusive { parts.append("≥ \(fmt(m, 6))") }
        if let m = maxInclusive { parts.append("≤ \(fmt(m, 6))") }
        if let m = minExclusive { parts.append("> \(fmt(m, 6))") }
        if let m = maxExclusive { parts.append("< \(fmt(m, 6))") }
        if let l = length { parts.append("\(l) characters") }
        return parts.isEmpty ? "any value" : parts.joined(separator: ", ")
    }
}

public struct IDSFacet: Hashable {
    public enum Kind: String { case entity, attribute, property, material, classification, partOf }
    public var kind: Kind
    /// entity: name/predefinedType; attribute: name/value; property: propertySet/baseName/value; material: value.
    public var name = IDSValue(), predefinedType = IDSValue(), value = IDSValue(), propertySet = IDSValue()
    /// "required", "optional", "prohibited".
    public var cardinality = "required"
    public var instructions = ""
}

public struct IDSSpecification: Hashable {
    public var name: String
    public var ifcVersion: String
    public var applicability: [IDSFacet] = []
    public var requirements: [IDSFacet] = []
    /// Applicability cardinality from minOccurs/maxOccurs ("required" = at least one applicable instance).
    public var cardinality = "optional"
}

public struct IDSResult: Hashable {
    public var specification: String
    public var applicable: Int
    public var failed: [Int: [String]]      // STEP id → reasons
    public var passed: Bool { failed.isEmpty }
    public var notes: [String]
}

public enum IDSValidator {
    public enum IDSError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid IDS: \(m)" }; return nil }
    }

    public static func parse(_ data: Data) throws -> [IDSSpecification] {
        let p = IDSParser()
        let x = XMLParser(data: data)
        x.shouldProcessNamespaces = true
        x.delegate = p
        guard x.parse() else { throw IDSError.invalid(x.parserError?.localizedDescription ?? "XML error") }
        guard !p.specs.isEmpty else { throw IDSError.invalid("no specifications") }
        return p.specs
    }

    /// Index of common attributes by IFC entity (IfcRoot / IfcObject / IfcProduct / IfcElement ordering).
    static func attributeIndex(_ name: String, type: String) -> Int? {
        switch name {
        case "GlobalId": return 0
        case "Name": return 2
        case "Description": return 3
        case "ObjectType": return 4
        case "Tag": return 7
        case "LongName": return ["IFCSPACE", "IFCBUILDINGSTOREY", "IFCBUILDING", "IFCSITE", "IFCPROJECT"].contains(type) ? (type == "IFCPROJECT" ? 5 : 7) : nil
        case "OverallHeight": return ["IFCDOOR", "IFCWINDOW"].contains(type) ? 8 : nil
        case "OverallWidth": return ["IFCDOOR", "IFCWINDOW"].contains(type) ? 9 : nil
        case "Elevation": return type == "IFCBUILDINGSTOREY" ? 9 : nil
        default: return nil
        }
    }
    /// PredefinedType position (last attribute of IFC4 element occurrences).
    static func predefinedIndex(_ e: StepEntity) -> Int? {
        switch e.type {
        case "IFCDOOR", "IFCWINDOW": return 10
        case "IFCSPACE": return 9
        case "IFCFURNISHINGELEMENT": return nil
        default: return e.args.count >= 9 ? 8 : nil
        }
    }

    public static func validate(ids specs: [IDSSpecification], ifc text: String) throws -> [IDSResult] {
        let f = try STEPParser.parse(text)
        // Property sets and materials per product.
        var psets: [Int: [String: [String: String]]] = [:]
        var materials: [Int: [String]] = [:]
        for r in f.all("IFCRELDEFINESBYPROPERTIES") {
            guard let ps = f[r[5].ref], ps.type == "IFCPROPERTYSET", let psName = ps[2].string else { continue }
            var props: [String: String] = [:]
            for pr in ps[4].refs { if let p = f[pr], p.type == "IFCPROPERTYSINGLEVALUE", let n = p[0].string { props[n] = p[2].text ?? "" } }
            for o in r[4].refs { psets[o, default: [:]][psName, default: [:]].merge(props) { $1 } }
        }
        func materialNames(_ id: Int?) -> [String] {
            guard let m = f[id] else { return [] }
            switch m.type {
            case "IFCMATERIAL": return m[0].string.map { [$0] } ?? []
            case "IFCMATERIALLAYERSETUSAGE": return materialNames(m[0].ref)
            case "IFCMATERIALLAYERSET": return m[0].refs.flatMap { l in materialNames(f[l]?[0].ref) } + (m[1].string.map { [$0] } ?? [])
            case "IFCMATERIALLIST": return m[0].refs.flatMap { materialNames($0) }
            default: return m[0].string.map { [$0] } ?? []
            }
        }
        for r in f.all("IFCRELASSOCIATESMATERIAL") { for o in r[4].refs { materials[o, default: []] += materialNames(r[5].ref) } }

        let products = f.entities.values.filter { $0.type.hasPrefix("IFC") && $0[0].string.map(IFCExporter.isValidGuid) == true }.sorted { $0.id < $1.id }
        var out: [IDSResult] = []
        for sp in specs {
            var notes: [String] = []
            func check(_ facet: IDSFacet, _ e: StepEntity) -> (ok: Bool, reason: String) {
                switch facet.kind {
                case .entity:
                    let t = e.type
                    let nameOK = facet.name.isEmpty || facet.name.matches(t, caseInsensitive: true) || facet.name.matches(t.replacingOccurrences(of: "STANDARDCASE", with: ""), caseInsensitive: true)
                    var predOK = true
                    if !facet.predefinedType.isEmpty {
                        let pv = predefinedIndex(e).flatMap { e[$0].enumValue } ?? ""
                        predOK = facet.predefinedType.matches(pv, caseInsensitive: true) || (pv == "USERDEFINED" && facet.predefinedType.matches(e[4].string ?? "", caseInsensitive: true))
                    }
                    return (nameOK && predOK, "is \(t) not \(facet.name.description)")
                case .attribute:
                    guard let an = facet.name.simple else { return (false, "attribute facet without a simple name") }
                    guard let i = attributeIndex(an, type: e.type) else { return (false, "attribute \(an) is not available for \(e.type)") }
                    let v = e[i].text ?? e[i].enumValue ?? ""
                    let present = !e[i].isNull && !v.isEmpty
                    guard present else { return (false, "attribute \(an) is empty") }
                    return (facet.value.isEmpty || facet.value.matches(v), "attribute \(an) = '\(v)' is not \(facet.value.description)")
                case .property:
                    let sets = psets[e.id] ?? [:]
                    let matchingSets = sets.filter { facet.propertySet.isEmpty || facet.propertySet.matches($0.key) }
                    guard let bn = facet.name.simple ?? facet.name.enumeration.first else { return (false, "property facet without baseName") }
                    let values = matchingSets.compactMap { $0.value[bn] }
                    guard !values.isEmpty else { return (false, "property \(facet.propertySet.description).\(bn) is missing") }
                    let ok = facet.value.isEmpty || values.contains { facet.value.matches($0) }
                    return (ok, "property \(bn) = '\(values.first ?? "")' is not \(facet.value.description)")
                case .material:
                    let ms = materials[e.id] ?? []
                    guard !ms.isEmpty else { return (false, "has no material") }
                    return (facet.value.isEmpty || ms.contains { facet.value.matches($0, caseInsensitive: true) }, "material \(ms.joined(separator: ", ")) is not \(facet.value.description)")
                case .classification, .partOf:
                    return (true, "")
                }
            }
            if sp.applicability.contains(where: { $0.kind == .classification || $0.kind == .partOf }) || sp.requirements.contains(where: { $0.kind == .classification || $0.kind == .partOf }) {
                notes.append("classification/partOf facets are not checked")
            }
            let applicable = products.filter { e in sp.applicability.allSatisfy { check($0, e).ok } }
            var failed: [Int: [String]] = [:]
            for e in applicable {
                for r in sp.requirements where r.kind != .classification && r.kind != .partOf {
                    let (ok, why) = check(r, e)
                    switch r.cardinality {
                    case "prohibited": if ok { failed[e.id, default: []].append("prohibited: " + r.kind.rawValue + " " + (r.name.simple ?? r.value.description) + " is present") }
                    case "optional":
                        // Optional: absent is fine, present must match the value.
                        if !ok && !(why.contains("missing") || why.contains("is empty") || why.contains("has no material")) { failed[e.id, default: []].append(why) }
                    default: if !ok { failed[e.id, default: []].append(why) }
                    }
                }
            }
            if sp.cardinality == "required" && applicable.isEmpty { failed[0] = ["no applicable instances, but the specification is required"] }
            if sp.cardinality == "prohibited" && !applicable.isEmpty { for e in applicable { failed[e.id, default: []].append("applicable instances are prohibited") } }
            out.append(IDSResult(specification: sp.name, applicable: applicable.count, failed: failed, notes: notes))
        }
        return out
    }
}

final class IDSParser: NSObject, XMLParserDelegate {
    var specs: [IDSSpecification] = []
    var inApplicability = false, inRequirements = false
    var facet: IDSFacet?
    var target = ""          // which IDSValue of the facet: name, predefinedType, value, propertySet
    var value = IDSValue()
    var inValueElement = false
    var text = ""
    func facetKind(_ n: String) -> IDSFacet.Kind? {
        switch n { case "entity": return .entity; case "attribute": return .attribute; case "property": return .property
        case "material": return .material; case "classification": return .classification; case "partOf": return .partOf; default: return nil }
    }
    func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch n {
        case "specification":
            var s = IDSSpecification(name: a["name"] ?? "Specification \(specs.count + 1)", ifcVersion: a["ifcVersion"] ?? "IFC4")
            if let mn = a["minOccurs"], let mx = a["maxOccurs"] { s.cardinality = mx == "0" ? "prohibited" : (mn == "0" ? "optional" : "required") }
            specs.append(s)
        case "applicability":
            inApplicability = true
            if let mn = a["minOccurs"], let mx = a["maxOccurs"], !specs.isEmpty { specs[specs.count - 1].cardinality = mx == "0" ? "prohibited" : (mn == "0" ? "optional" : "required") }
        case "requirements": inRequirements = true
        default:
            if let k = facetKind(n), inApplicability || inRequirements, facet == nil {
                var f = IDSFacet(kind: k)
                if let c = a["cardinality"] { f.cardinality = c }
                else if let mn = a["minOccurs"], let mx = a["maxOccurs"] { f.cardinality = mx == "0" ? "prohibited" : (mn == "0" ? "optional" : "required") }
                f.instructions = a["instructions"] ?? ""
                facet = f
            } else if facet != nil, ["name", "predefinedType", "value", "propertySet", "baseName"].contains(n) {
                target = n == "baseName" ? "name" : n; value = IDSValue()
            } else if n == "restriction" { inValueElement = true }
            else if inValueElement || !target.isEmpty {
                switch n {
                case "enumeration": if let v = a["value"] { value.enumeration.append(v) }
                case "pattern": value.pattern = a["value"]
                case "minInclusive": value.minInclusive = a["value"].flatMap(Double.init)
                case "maxInclusive": value.maxInclusive = a["value"].flatMap(Double.init)
                case "minExclusive": value.minExclusive = a["value"].flatMap(Double.init)
                case "maxExclusive": value.maxExclusive = a["value"].flatMap(Double.init)
                case "length": value.length = a["value"].flatMap(Int.init)
                default: break
                }
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ parser: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
        switch n {
        case "simpleValue": value.simple = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "restriction": inValueElement = false
        case "name", "predefinedType", "value", "propertySet", "baseName":
            guard facet != nil, !target.isEmpty else { break }
            switch target {
            case "name": facet!.name = value
            case "predefinedType": facet!.predefinedType = value
            case "propertySet": facet!.propertySet = value
            default: facet!.value = value
            }
            target = ""
        case "applicability": inApplicability = false
        case "requirements": inRequirements = false
        default:
            if let k = facetKind(n), let f = facet, f.kind == k, !specs.isEmpty {
                if inRequirements { specs[specs.count - 1].requirements.append(f) } else { specs[specs.count - 1].applicability.append(f) }
                facet = nil
            }
        }
        text = ""
    }
}
